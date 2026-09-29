#!/bin/bash
#
# 本地隔离验证：用桩函数模拟 netifd 环境，跑一遍 setup / teardown，
# 检查生成的 wpa_supplicant 配置与 ubus 调用参数是否正确。
# 不触碰真实 /var/run，不联网，不需要路由器。
#
# 用法： bash tools/test_proto_locally.sh
#
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/net/ieee8021xclient/files/ieee8021xclient.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_RUN="$TMP/run"
FAKE_BIN="$TMP/bin"
UBUS_LOG="$TMP/ubus.log"
SYSLOG="$TMP/syslog"
mkdir -p "$FAKE_RUN" "$FAKE_BIN"
: > "$UBUS_LOG"; : > "$SYSLOG"

# ---- 桩：ubus ----
cat > "$FAKE_BIN/ubus" <<'EOS'
#!/bin/sh
echo "ubus $*" >> "$UBUS_LOG"
case "$1" in
	-S) [ "$WPA_PRESENT" = "1" ] || exit 1; exit 0 ;;
	call) [ "$UBUS_CALL_FAIL" = "1" ] && exit 1; exit 0 ;;
	wait_for)
		echo "FATAL: 不应调用无超时的 ubus wait_for" >&2
		sleep 300
		;;
esac
exit 0
EOS
chmod +x "$FAKE_BIN/ubus"

# ---- 桩：logger ----
printf '#!/bin/sh\necho "logger $*" >> "$SYSLOG"\n' > "$FAKE_BIN/logger"
chmod +x "$FAKE_BIN/logger"

export PATH="$FAKE_BIN:$PATH"
export WPA_PRESENT=1 UBUS_CALL_FAIL=0 UBUS_LOG SYSLOG

# ---- 桩：netifd 提供的函数 ----
json_get_vars() {
	local _v
	for _v in "$@"; do
		eval "$_v=\"\${CFG_$_v:-}\""
	done
}
proto_config_add_int() { :; }
proto_config_add_string() { :; }
proto_config_add_boolean() { :; }
proto_notify_error() { echo "proto_notify_error($1, $2)" >> "$TMP/notices"; }
proto_block_restart() { echo "proto_block_restart($1)" >> "$TMP/notices"; }
add_protocol() { :; }
init_proto() { :; }
export ERROR=0

# ---- 把脚本里的 /var/run/ 重定向到临时目录（脚本本体不被改动）----
PATCHED="$TMP/proto.sh"
sed "s|/var/run/|$FAKE_RUN/|g" "$SRC" > "$PATCHED"

PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
check()     { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
check_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
has_substr() { grep -F -q -e "$2" "$1"; }

reset_cfg() {
	local k
	for k in eapol_version identity anonymous_identity password ca_cert client_cert \
		private_key private_key_passwd dh_file subject_match phase1 phase2 \
		ca_cert2 client_cert2 private_key2 private_key2_passwd dh_file2 subject_match2 \
		eap eap_workaround; do
		eval "CFG_$k=''"
	done
}

INCLUDE_ONLY=1 . "$PATCHED"

echo "=== 1) 基本场景：生成的配置内容 ==="
reset_cfg
CFG_identity='user@campus'
CFG_password='secret'
CFG_eap='PEAP'
CFG_phase2='auth=MSCHAPV2'
CFG_eap_workaround='0'
( proto_ieee8021xclient_setup wan eth0 )
CONF="$FAKE_RUN/wpa_supplicant-eth0.conf"
echo "--- 生成内容 ---"; sed 's/^/    /' "$CONF"
check     "配置文件已生成"           test -f "$CONF"
check     "含 ap_scan=0"            has_substr "$CONF" 'ap_scan=0'
check     "含 key_mgmt=IEEE8021X"   has_substr "$CONF" 'key_mgmt=IEEE8021X'
check     "含 eapol_flags=0"        has_substr "$CONF" 'eapol_flags=0'
check     "identity 正确写出"        has_substr "$CONF" 'identity="user@campus"'
check     "password 正确写出"        has_substr "$CONF" 'password="secret"'
check     "eap 正确写出"            has_substr "$CONF" 'eap=PEAP'
check     "phase2 含空格被引号包裹"   has_substr "$CONF" 'phase2="auth=MSCHAPV2"'
check     "eap_workaround=0 未被写成 1" has_substr "$CONF" 'eap_workaround=0'
check_not "未写入空的 ca_cert 字段"   has_substr "$CONF" 'ca_cert='
check     "记录了接口->设备映射"      has_substr "$FAKE_RUN/ieee8021xclient-wan.ifname" 'eth0'
check     "config_add 用设备名 eth0"  has_substr "$UBUS_LOG" '"iface": "eth0"'
check     "config_add 带 driver=wired" has_substr "$UBUS_LOG" '"driver":"wired"'

echo
echo "=== 2) 特殊字符：密码含 空格/引号/反斜杠/# ==="
reset_cfg
CFG_identity='stu@x'
CFG_password='pa ss"wo\rd#1'
rm -f "$CONF"
( proto_ieee8021xclient_setup wan eth0 )
echo "--- 生成内容 ---"; sed 's/^/    /' "$CONF"
check "密码行被引号包裹"   has_substr "$CONF" 'password="pa ss'
check "双引号被转义为 \\\" " has_substr "$CONF" 'ss\"wo'
check "反斜杠被转义为 \\\\ " has_substr "$CONF" 'wo\\rd'
check "# 未被当成注释截断"  has_substr "$CONF" 'rd#1"'
check "密码字段只出现一行"  test "$(grep -c 'password=' "$CONF")" -eq 1

echo
echo "=== 3) teardown：必须移除设备名而非接口名 ==="
: > "$UBUS_LOG"
( proto_ieee8021xclient_teardown wan eth0 )
echo "--- ubus 调用 ---"; sed 's/^/    /' "$UBUS_LOG"
check     "config_remove 用设备名 eth0" has_substr "$UBUS_LOG" '{"iface":"eth0"}'
check_not "未误用接口名 wan"            has_substr "$UBUS_LOG" '{"iface":"wan"}'
check     "清理了映射文件"              test ! -f "$FAKE_RUN/ieee8021xclient-wan.ifname"

echo
echo "=== 4) teardown 第二参数缺失时回退到映射文件 ==="
: > "$UBUS_LOG"
echo 'eth0' > "$FAKE_RUN/ieee8021xclient-wan.ifname"
( proto_ieee8021xclient_teardown wan "" )
check "回退后仍移除 eth0" has_substr "$UBUS_LOG" '{"iface":"eth0"}'

echo
echo "=== 5) wpa_supplicant 缺席：必须有界放弃，不得挂住 ==="
reset_cfg
CFG_identity='u'
export WPA_PRESENT=0 IEEE8021X_WPA_WAIT=2
START=$(date +%s)
( proto_ieee8021xclient_setup wan eth0 ); RC=$?
END=$(date +%s)
echo "    返回码=$RC  耗时=$((END-START))s"
check "setup 返回非零"         test "$RC" -ne 0
check "在限定时间内返回(<10s)"  test $((END-START)) -lt 10
check "记录了放弃原因"          has_substr "$SYSLOG" 'wpa_supplicant ubus object unavailable'
export WPA_PRESENT=1 IEEE8021X_WPA_WAIT=15

echo
echo "=== 6) config_add 失败：不得静默 ==="
reset_cfg
CFG_identity='u'
export UBUS_CALL_FAIL=1
( proto_ieee8021xclient_setup wan eth0 ); RC=$?
check "失败被记录到 syslog"     has_substr "$SYSLOG" 'config_add failed'
check "不改变原有退出码(0)"     test "$RC" -eq 0
export UBUS_CALL_FAIL=0

echo
echo "=== 7) 配置文件不可写：必须报错返回 ==="
reset_cfg
CFG_identity='u'
chmod 500 "$FAKE_RUN"
( proto_ieee8021xclient_setup wan eth1 ); RC=$?
chmod 700 "$FAKE_RUN"
check "写失败返回非零" test "$RC" -ne 0
check "写失败被记录"   has_substr "$SYSLOG" 'failed to write'

echo
echo "=== 8) 静态检查 ==="
check     "sh -n 语法通过"                    sh -n "$SRC"
check_not "代码中无无超时的 ubus wait_for"     grep -n "^[^#]*ubus wait_for" "$SRC"
check_not "无旧的错误字段名 private_key_passwd2" grep -q 'private_key_passwd2' "$SRC"
check     "Phase2 私钥字段名正确"              grep -q 'private_key2_passwd' "$SRC"
check     "protocol JS 语法通过"               node --check "$REPO/luci-proto-ieee8021xclient/htdocs/luci-static/resources/protocol/ieee8021xclient.js"

echo
echo "=========== 结果：PASS=$PASS FAIL=$FAIL ==========="
[ "$FAIL" -eq 0 ]
