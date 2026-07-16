#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

xcrun clang -dynamiclib -arch x86_64 -O2 "$root/runtime/dns-gate.c" -lresolv -o "$stage/gate.dylib"
xcrun swiftc -O "$root/runtime/window-probe.swift" -o "$stage/window-probe"
printf '%s\n' \
  '#include <netdb.h>' \
  '#include <resolv.h>' \
  'int main(int count,char **values){unsigned char answer[512];if(count>2)return res_query(values[1],1,1,answer,512)<0?1:0;struct addrinfo *result=0;int code=getaddrinfo(values[1],0,0,&result);if(result)freeaddrinfo(result);return code==0?0:1;}' \
  | xcrun clang -arch x86_64 -x c - -lresolv -o "$stage/resolver"

gate="$stage/enabled"
dns_log="$stage/dns.log"
touch "$gate"
run_resolver() {
  env \
    DYLD_INSERT_LIBRARIES="$stage/gate.dylib" \
    MHG_DNS_GATE_FILE="$gate" \
    MHG_DNS_GATE_OWNER_PID="$$" \
    MHG_DNS_LOG_FILE="$dns_log" \
    "$stage/resolver" "$@"
}
if run_resolver dispatchcnglobal.yuanshen.com; then
  printf '域名门控未屏蔽目标域名。\n' >&2
  exit 1
fi
run_resolver dispatchcnglobal.yuanshen.com
touch "$gate"
if run_resolver dispatchosglobal.yuanshen.com dns; then
  printf '域名门控未屏蔽 Wine DNS 查询路径。\n' >&2
  exit 1
fi
run_resolver localhost
rm -f "$gate"
run_resolver dispatchcnglobal.yuanshen.com
grep -q $'getaddrinfo/ANY\tdispatchcnglobal.yuanshen.com\tblocked' "$dns_log"
grep -q $'getaddrinfo/ANY\tdispatchcnglobal.yuanshen.com\tallowed\t0\t' "$dns_log"
grep -q $'res_query\tdispatchosglobal.yuanshen.com\tblocked' "$dns_log"
test ! -e "$gate"
if "$stage/window-probe" invalid; then
  printf '窗口探针未拒绝无效进程组。\n' >&2
  exit 1
fi
printf '游戏运行时宿主组件测试通过。\n'
