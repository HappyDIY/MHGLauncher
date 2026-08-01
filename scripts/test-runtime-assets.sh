#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

source_lock="$root/packaging/game-runtime-source-lock.json"
jq -e '
  .schemaVersion == 2 and
  .wineBuild.version == "wine-11.0-mhg3" and
  (has("wineArtifact") | not) and
  .wineBuild.sourceId == "codeweavers-wine" and
  .wineBuild.patchSourceId == "macports-game-patches" and
  (.wineBuild.localPatches | length > 0 and
    all((.path | startswith("packaging/patches/")) and
      (.sha256 | test("^[0-9a-f]{64}$")))) and
  ([.sources[].id] | sort == ["codeweavers-wine","freetype","macports-game-patches"]) and
  all(.sources[];
    (.url | startswith("https://")) and
    (.sha256 | test("^[0-9a-f]{64}$")) and
    (.cacheFile | test("^[A-Za-z0-9._-]+$"))) and
  ([.buildTools[].id] | sort == ["bison","llvm-mingw"]) and
  all(.buildTools[];
    (.url | startswith("https://")) and
    (.sha256 | test("^[0-9a-f]{64}$")) and
    (.cacheFile | test("^[A-Za-z0-9._-]+$")))
' "$source_lock" >/dev/null

bash -n "$root/scripts/build-wine-runtime.sh"
grep -q -- '--enable-archs=i386,x86_64' "$root/scripts/build-wine-runtime.sh"
grep -q -- '--with-mingw=llvm-mingw' "$root/scripts/build-wine-runtime.sh"
grep -q -- '--with-freetype' "$root/scripts/build-wine-runtime.sh"
grep -q -- 'libfreetype.6.dylib' "$root/scripts/build-wine-runtime.sh"
grep -q -- 'game-runtime/wine/lib/libfreetype.6.dylib' "$root/scripts/build-runtime-assets.sh"
grep -q -- 'game-runtime/wine/lib/wine/x86_64-windows/wineconsole.exe' "$root/scripts/build-runtime-assets.sh"
grep -q -- 'game-runtime/wine/lib/wine/x86_64-windows/winecfg.exe' "$root/scripts/build-runtime-assets.sh"
grep -q -- '--package-lock-only' "$root/scripts/build-runtime-assets.sh"
if grep -q -- '--without-freetype' "$root/scripts/build-wine-runtime.sh"; then
  printf 'Wine 构建禁用了首选项窗口所需的字体引擎。\n' >&2
  exit 1
fi
if grep -q -- '--enable-win64' "$root/scripts/build-wine-runtime.sh"; then
  printf 'Wine 构建仍是不能运行 Win32 程序的纯 Win64 配置。\n' >&2
  exit 1
fi
while IFS= read -r local_patch; do
  patch_path="$root/$(jq -r '.path' <<<"$local_patch")"
  test -f "$patch_path"
  test "$(shasum -a 256 "$patch_path" | awk '{print $1}')" = "$(jq -r '.sha256' <<<"$local_patch")"
done < <(jq -c '.wineBuild.localPatches[]' "$source_lock")
if rg -i 'yaagl|anime-game-wine' \
  "$root/scripts/fetch-game-runtime.sh" \
  "$root/scripts/build-wine-runtime.sh" \
  "$source_lock"; then
  printf 'Wine 构建链仍引用第三方预编译运行时。\n' >&2
  exit 1
fi

if "$root/scripts/build-runtime-assets.sh" '../../outside' >/dev/null 2>&1; then
  printf '构建脚本接受了不安全 tag。\n' >&2
  exit 1
fi
if "$root/scripts/publish-runtime-assets.sh" '../../outside' >/dev/null 2>&1; then
  printf '发布脚本接受了不安全 tag。\n' >&2
  exit 1
fi
if "$root/scripts/build-runtime-assets.sh" v0.2.0 >/dev/null 2>&1; then
  printf '构建脚本接受了与 App 版本不一致的 tag。\n' >&2
  exit 1
fi

manifest="$("$root/scripts/create-smoke-runtime-assets.sh" "$stage/assets" v0.1.1)"
jq -e '.schemaVersion == 2 and .tag == "v0.1.1" and .appVersion == "0.1.1" and .platform == "darwin" and .hostArchitecture == "arm64"' "$manifest" >/dev/null
"$root/scripts/verify-runtime-assets.sh" "$stage/assets" core >/dev/null

jq -c '.components[]' "$manifest" | while IFS= read -r component; do
  file="$(jq -r '.file' <<<"$component")"
  path="$stage/assets/$file"
  test -f "$path"
  test "$(stat -f %z "$path")" = "$(jq -r '.size' <<<"$component")"
  test "$(shasum -a 256 "$path" | awk '{print $1}')" = "$(jq -r '.sha256' <<<"$component")"
done

tampered="$(jq -r '.components[0].file' "$manifest")"
printf 'tamper' >>"$stage/assets/$tampered"
if "$root/scripts/verify-runtime-assets.sh" "$stage/assets" core >/dev/null 2>&1; then
  printf '资产校验接受了被篡改的归档。\n' >&2
  exit 1
fi

fake="$stage/fake-bin"
mkdir -p "$fake"
cat >"$fake/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--json isDraft"* ]]; then printf 'false\n'; exit 0; fi
exit 1
EOF
chmod +x "$fake/gh"
if PATH="$fake:$PATH" "$root/scripts/publish-runtime-assets.sh" v0.1.1 >/dev/null 2>&1; then
  printf '发布脚本允许修改公开 Release。\n' >&2
  exit 1
fi

app="$root/dist/MHGLauncher.app"
if [[ -d "$app" ]]; then
  test ! -e "$app/Contents/Resources/Backend/node"
  test ! -e "$app/Contents/Resources/Backend/MHGLauncherBackend/node"
  test ! -e "$app/Contents/Resources/GameRuntime"
fi

printf '运行时资产清单测试通过。\n'
