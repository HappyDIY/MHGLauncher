#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

"$root/scripts/build-dns-gate.sh" "$stage/gate.dylib"
xcrun swiftc -O "$root/runtime/window-probe.swift" -o "$stage/window-probe"
printf '%s\n' \
  '#include <netdb.h>' \
  '#include <resolv.h>' \
  '#include <string.h>' \
  'int main(int count,char **values){unsigned char answer[512];if(count>2&&strcmp(values[2],"dns")==0)return res_query(values[1],1,1,answer,512)<0?1:0;if(count>2&&strcmp(values[2],"host")==0)return gethostbyname(values[1])?0:1;if(count>2&&strcmp(values[2],"host2")==0)return gethostbyname2(values[1],AF_INET6)?0:1;struct addrinfo *result=0;int code=getaddrinfo(values[1],0,0,&result);if(result)freeaddrinfo(result);return code==0?0:1;}' \
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
touch "$gate"
if run_resolver dispatchcnglobal.yuanshen.com host; then
  printf '域名门控未屏蔽旧版 IPv4 查询路径。\n' >&2
  exit 1
fi
touch "$gate"
if run_resolver dispatchosglobal.yuanshen.com host2; then
  printf '域名门控未屏蔽旧版 IPv6 查询路径。\n' >&2
  exit 1
fi
run_resolver localhost
rm -f "$gate"
run_resolver dispatchcnglobal.yuanshen.com
grep -q $'getaddrinfo/ANY\tdispatchcnglobal.yuanshen.com\tblocked' "$dns_log"
grep -q $'getaddrinfo/ANY\tdispatchcnglobal.yuanshen.com\tallowed\t0\t' "$dns_log"
grep -q $'res_query\tdispatchosglobal.yuanshen.com\tblocked' "$dns_log"
grep -q $'gethostbyname\tdispatchcnglobal.yuanshen.com\tblocked' "$dns_log"
grep -q $'gethostbyname2\tdispatchosglobal.yuanshen.com\tblocked' "$dns_log"
test ! -e "$gate"
if "$stage/window-probe" invalid; then
  printf '窗口探针未拒绝无效进程组。\n' >&2
  exit 1
fi
printf '%s\n' \
  '#include <unistd.h>' \
  'int main(void){sleep(30);return 0;}' \
  | xcrun clang -arch arm64 -x c - -o "$stage/YuanShen.exe"
"$stage/YuanShen.exe" &
game_pid="$!"
trap 'kill "$game_pid" 2>/dev/null || true; rm -rf "$stage"' EXIT
game_snapshot="$("$stage/window-probe" --snapshot | paste -sd, -)"
if "$stage/window-probe" "$game_pid" "$game_snapshot"; then
  printf '窗口探针错误接受了快照中已存在的游戏进程。\n' >&2
  exit 1
fi
window_snapshot="$(printf '%s\n' "$game_snapshot" | tr ',' '\n' | awk '!/^p:/' | paste -sd, -)"
set +e
"$stage/window-probe" "$game_pid" "$window_snapshot"
probe_status="$?"
set -e
if [[ "$probe_status" != "3" ]]; then
  printf '窗口探针未区分已创建进程与可见窗口。\n' >&2
  exit 1
fi
kill "$game_pid"
wait "$game_pid" 2>/dev/null || true
printf '游戏运行时宿主组件测试通过。\n'
