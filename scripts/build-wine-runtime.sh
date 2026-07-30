#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?用法: build-wine-runtime.sh <输出目录>}"
lock="$root/packaging/game-runtime-source-lock.json"
source_cache="${MHG_SOURCE_CACHE:-$HOME/Library/Caches/MHGLauncher/sources}"
tool_cache="${MHG_TOOL_CACHE:-$HOME/Library/Caches/MHGLauncher/source-tools}"
jobs="${MHG_BUILD_JOBS:-$(sysctl -n hw.logicalcpu)}"

read_lock() { jq -er "$1" "$lock"; }
fetch() {
  local url="$1" sha="$2" destination="$3"
  if [[ ! -f "$destination" ]] || [[ "$(shasum -a 256 "$destination" | awk '{print $1}')" != "$sha" ]]; then
    rm -f "$destination.tmp"
    curl --fail --location --retry 3 --output "$destination.tmp" "$url"
    [[ "$(shasum -a 256 "$destination.tmp" | awk '{print $1}')" == "$sha" ]]
    mv "$destination.tmp" "$destination"
  fi
}
fetch_entry() {
  local kind="$1" id="$2" destination="$3"
  fetch \
    "$(jq -er --arg id "$id" ".${kind}[] | select(.id == \$id) | .url" "$lock")" \
    "$(jq -er --arg id "$id" ".${kind}[] | select(.id == \$id) | .sha256" "$lock")" \
    "$destination"
}

[[ "$(uname -s)" == "Darwin" ]]
[[ "$(uname -m)" == "arm64" ]]
command -v jq >/dev/null
command -v xcrun >/dev/null
mkdir -p "$source_cache" "$tool_cache"

wine_id="$(read_lock '.wineBuild.sourceId')"
patch_id="$(read_lock '.wineBuild.patchSourceId')"
wine_archive="$source_cache/$(read_lock ".sources[] | select(.id == \"$wine_id\") | .cacheFile")"
patch_archive="$source_cache/$(read_lock ".sources[] | select(.id == \"$patch_id\") | .cacheFile")"
freetype_archive="$source_cache/$(read_lock '.sources[] | select(.id == "freetype") | .cacheFile')"
bison_archive="$tool_cache/$(read_lock '.buildTools[] | select(.id == "bison") | .cacheFile')"
mingw_archive="$tool_cache/$(read_lock '.buildTools[] | select(.id == "llvm-mingw") | .cacheFile')"
fetch_entry sources "$wine_id" "$wine_archive"
fetch_entry sources "$patch_id" "$patch_archive"
fetch_entry sources freetype "$freetype_archive"
fetch_entry buildTools bison "$bison_archive"
fetch_entry buildTools llvm-mingw "$mingw_archive"

bison_version="$(read_lock '.buildTools[] | select(.id == "bison") | .version')"
bison_prefix="$tool_cache/bison-$bison_version-install"
if [[ ! -x "$bison_prefix/bin/bison" ]]; then
  bison_stage="$(mktemp -d)"
  tar -xf "$bison_archive" -C "$bison_stage"
  (
    cd "$bison_stage/bison-$bison_version"
    ./configure --prefix="$bison_prefix" >/dev/null
    make -s -j "$jobs"
    make -s install
  )
fi

mingw_version="$(read_lock '.buildTools[] | select(.id == "llvm-mingw") | .version')"
mingw_prefix="$tool_cache/llvm-mingw-$mingw_version"
if [[ ! -x "$mingw_prefix/bin/x86_64-w64-mingw32-clang" ]]; then
  mingw_stage="$(mktemp -d)"
  tar -xf "$mingw_archive" -C "$mingw_stage"
  extracted="$(find "$mingw_stage" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$extracted" ]]
  mv "$extracted" "$mingw_prefix"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/source" "$stage/patches" "$stage/build" "$stage/install"
tar -xf "$wine_archive" -C "$stage/source"
tar -xf "$patch_archive" -C "$stage/patches"
tar -xf "$freetype_archive" -C "$stage/source"
source_root="$stage/source/$(read_lock ".sources[] | select(.id == \"$wine_id\") | .sourceRoot")"
freetype_root="$stage/source/$(read_lock '.sources[] | select(.id == "freetype") | .sourceRoot')"
[[ "$(cat "$source_root/VERSION")" == "Wine version 11.0" ]]
while IFS= read -r local_patch; do
  local_path="$root/$(jq -r '.path' <<<"$local_patch")"
  [[ "$(shasum -a 256 "$local_path" | awk '{print $1}')" == "$(jq -r '.sha256' <<<"$local_patch")" ]]
  patch -d "$source_root" -p1 <"$local_path"
done < <(jq -c '.wineBuild.localPatches[]' "$lock")
while IFS= read -r patch_path; do
  patch -d "$source_root" -p1 <"$stage/patches/$patch_path"
done < <(read_lock ".sources[] | select(.id == \"$patch_id\") | .patches[]")

prefix="$(read_lock '.wineBuild.buildPrefix')"
(
  cd "$freetype_root"
  CC="/usr/bin/clang -arch x86_64" CFLAGS="-O2 -arch x86_64" LDFLAGS="-arch x86_64" \
    "$freetype_root/configure" --host=x86_64-apple-darwin --prefix="$stage/freetype-install" \
    --disable-static --enable-shared --with-zlib=no --with-bzip2=no --with-png=no \
    --with-harfbuzz=no --with-brotli=no >/dev/null
  make -s -j "$jobs" >/dev/null
  make -s install >/dev/null
)
configure=(
  "$source_root/configure" --build=x86_64-apple-darwin --prefix="$prefix"
  --enable-archs=i386,x86_64 --disable-tests --with-mingw=llvm-mingw
  --without-alsa --without-capi --with-coreaudio --without-cups --without-dbus
  --without-fontconfig --with-freetype --without-gettext --without-gphoto
  --without-gnutls --without-gssapi --without-gstreamer --without-krb5
  --without-netapi --without-opencl --without-opengl --without-oss --without-pcap
  --without-pcsclite --without-pulse --without-sane --without-sdl --without-udev
  --without-unwind --without-usb --without-v4l2 --without-vulkan --without-wayland --without-x
)
(
  cd "$stage/build"
  PATH="$bison_prefix/bin:$mingw_prefix/bin:/usr/bin:/bin" \
    FREETYPE_CFLAGS="-I$stage/freetype-install/include/freetype2" \
    FREETYPE_LIBS="-L$stage/freetype-install/lib -lfreetype" \
    CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" \
    CFLAGS="-O2 -arch x86_64" LDFLAGS="-arch x86_64" "${configure[@]}"
  PATH="$bison_prefix/bin:$mingw_prefix/bin:/usr/bin:/bin" make -s -j "$jobs" install-lib DESTDIR="$stage/install"
)

built="$stage/install$prefix"
[[ -x "$built/bin/wine" && -x "$built/bin/wineserver" ]]
[[ -f "$built/lib/wine/x86_64-windows/wineboot.exe" ]]
[[ -f "$built/lib/wine/i386-windows/rundll32.exe" ]]
ln -s wine "$built/bin/wineboot"
[[ -f "$built/lib/wine/x86_64-unix/ntdll.so" ]]
grep -R -a -q 'WINEMSYNC' "$built/lib/wine"
grep -R -a -q 'FT_Init_FreeType' "$built/lib/wine"
cp "$stage/freetype-install/lib/libfreetype.6.dylib" "$built/lib/"
install_name_tool -id '@rpath/libfreetype.6.dylib' "$built/lib/libfreetype.6.dylib"
while IFS= read -r module; do
  install_name_tool -add_rpath '@loader_path/../..' "$module"
done < <(grep -R -a -l 'libfreetype.6.dylib' "$built/lib/wine/x86_64-unix")
mkdir -p "$built/share/licenses"
cp "$freetype_root/docs/FTL.TXT" "$built/share/licenses/FreeType-FTL.txt"
rm -rf "$output"
mkdir -p "$(dirname "$output")"
cp -R "$built" "$output"
find "$output" -type f -perm -111 -exec codesign --force --sign - {} \; 2>/dev/null || true
[[ "$("$output/bin/wine" --version)" == "wine-11.0" ]]

jq -n \
  --arg version "$(read_lock '.wineBuild.version')" \
  --arg sourceSha "$(read_lock ".sources[] | select(.id == \"$wine_id\") | .sha256")" \
  --arg patchSha "$(read_lock ".sources[] | select(.id == \"$patch_id\") | .sha256")" \
  --arg freetypeSha "$(read_lock '.sources[] | select(.id == "freetype") | .sha256')" \
  --arg compilerSha "$(read_lock '.buildTools[] | select(.id == "llvm-mingw") | .sha256')" \
  '{schemaVersion:1, version:$version, sourceSha256:$sourceSha,
    patchSetSha256:$patchSha, freetypeSha256:$freetypeSha,
    compilerSha256:$compilerSha, locallyCompiled:true}' \
  >"$output/BUILD_PROVENANCE.json"
printf 'Wine 已从固定源码自主编译：%s\n' "$output"
