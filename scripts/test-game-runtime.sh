#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

xcrun clang -dynamiclib -arch x86_64 -O2 "$root/runtime/dns-gate.c" -lresolv -o "$stage/gate.dylib"
xcrun swiftc -O "$root/runtime/window-probe.swift" -o "$stage/window-probe"
printf '%s\n' \
  '#include <netdb.h>' \
  'int main(int count,char **values){struct addrinfo *result=0;int code=getaddrinfo(values[1],0,0,&result);if(result)freeaddrinfo(result);return code==0?0:1;}' \
  | xcrun clang -arch x86_64 -x c - -o "$stage/resolver"

gate="$stage/enabled"
touch "$gate"
export DYLD_INSERT_LIBRARIES="$stage/gate.dylib"
export MHG_DNS_GATE_FILE="$gate"
export MHG_DNS_GATE_OWNER_PID="$$"
if "$stage/resolver" dispatchcnglobal.yuanshen.com; then
  printf '域名门控未屏蔽目标域名。\n' >&2
  exit 1
fi
"$stage/resolver" localhost
rm "$gate"
"$stage/resolver" dispatchcnglobal.yuanshen.com
unset DYLD_INSERT_LIBRARIES MHG_DNS_GATE_FILE MHG_DNS_GATE_OWNER_PID

if "$stage/window-probe" invalid; then
  printf '窗口探针未拒绝无效进程组。\n' >&2
  exit 1
fi
printf '游戏运行时宿主组件测试通过。\n'
