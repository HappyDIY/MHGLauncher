#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

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

manifest="$("$root/scripts/create-smoke-runtime-assets.sh" "$stage/assets" v0.1.0)"
jq -e '.schemaVersion == 2 and .tag == "v0.1.0" and .appVersion == "0.1.0" and .platform == "darwin" and .hostArchitecture == "arm64"' "$manifest" >/dev/null
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
if PATH="$fake:$PATH" "$root/scripts/publish-runtime-assets.sh" v0.1.0 >/dev/null 2>&1; then
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
