#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

# 等待 wpa_supplicant ubus 对象出现的上限（秒）。
# 超时后放弃本次 setup 并让 netifd 稍后重试，绝不用无超时的 ubus wait_for
# 把接口永久卡在 setup 阶段。
IEEE8021X_WPA_WAIT="${IEEE8021X_WPA_WAIT:-15}"

ieee8021xclient_exitcode_tostring() {
	local errorcode=$1
	[ -n "$errorcode" ] || errorcode=5

	case "$errorcode" in
		0) echo "OK" ;;
		1) echo "FATAL_ERROR" ;;
		2) echo "OPTION_ERROR" ;;
		5) echo "USER_REQUEST" ;;
		*) echo "UNKNOWN_ERROR" ;;
	esac
}

_ieee8021xclient_log() {
	logger -t ieee8021xclient "$@"
}

# 生成 wpa_supplicant.conf 的一行 "key=value"。
# 值为空则整行省略（保持与上游一致的行为）；否则统一加双引号并转义 \ 与 "，
# 避免密码/用户名里的空格、引号、# 破坏配置或注入额外字段。
_ieee8021xclient_field() {
	local key="$1"
	local value="$2"
	local escaped

	[ -n "$value" ] || return 0

	escaped=$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
	printf '\t%s="%s"\n' "$key" "$escaped"
}

# 有界等待 wpa_supplicant ubus 对象；0 表示不等待（立即返回失败）
ieee8021xclient_wait_wpa_supplicant() {
	local waited=0

	while [ "$waited" -lt "$IEEE8021X_WPA_WAIT" ]; do
		ubus -S list wpa_supplicant >/dev/null 2>&1 && return 0
		sleep 1
		waited=$((waited + 1))
	done

	return 1
}

_wpa_supplicant_common() {
	local ifname="$1"

	_config="/var/run/wpa_supplicant-$ifname.conf"
}

proto_ieee8021xclient_setup() {
	local cfg="$1"
	local ifname="$2"

	local eapol_version
	local identity anonymous_identity password
	local ca_cert client_cert private_key private_key_passwd dh_file subject_match
	local phase1 phase2 ca_cert2 client_cert2 private_key2 private_key2_passwd dh_file2 subject_match2
	local eap eap_workaround
	json_get_vars eapol_version
	json_get_vars identity anonymous_identity password
	json_get_vars ca_cert client_cert private_key private_key_passwd dh_file subject_match
	json_get_vars phase1 phase2 ca_cert2 client_cert2 private_key2 private_key2_passwd dh_file2 subject_match2
	json_get_vars eap eap_workaround

	local _config
	_wpa_supplicant_common "$ifname"

	# 等待 wpa_supplicant 就绪；不就绪就放弃本次尝试，交由 netifd 重试，
	# 而不是无限期挂住这个接口。
	if ! ieee8021xclient_wait_wpa_supplicant; then
		_ieee8021xclient_log "wpa_supplicant ubus object unavailable after ${IEEE8021X_WPA_WAIT}s (interface $cfg, device $ifname); aborting setup"
		return 1
	fi

	# 记录接口 -> 设备 的对应关系，供 teardown 精确移除（见 proto_ieee8021xclient_teardown）
	[ -n "$cfg" ] && echo "$ifname" > "/var/run/ieee8021xclient-$cfg.ifname"

	# 有线 802.1X 的认证方是交换机端口：wpa_supplicant 不应扫描 AP（ap_scan=0），
	# 也不应期待无线的成对密钥/预认证（eapol_flags=0），密钥管理必须是 IEEE8021X。
	{
		[ -n "$eapol_version" ] && printf 'eapol_version="%s"\n' "$eapol_version"
		printf 'ap_scan=0\n'
		printf 'network={\n'
		printf '\tkey_mgmt=IEEE8021X\n'
		printf '\teapol_flags=0\n'
		_ieee8021xclient_field identity "$identity"
		_ieee8021xclient_field anonymous_identity "$anonymous_identity"
		_ieee8021xclient_field password "$password"
		_ieee8021xclient_field ca_cert "$ca_cert"
		_ieee8021xclient_field client_cert "$client_cert"
		_ieee8021xclient_field private_key "$private_key"
		_ieee8021xclient_field private_key_passwd "$private_key_passwd"
		_ieee8021xclient_field dh_file "$dh_file"
		_ieee8021xclient_field subject_match "$subject_match"
		_ieee8021xclient_field phase1 "$phase1"
		_ieee8021xclient_field phase2 "$phase2"
		_ieee8021xclient_field ca_cert2 "$ca_cert2"
		_ieee8021xclient_field client_cert2 "$client_cert2"
		_ieee8021xclient_field private_key2 "$private_key2"
		_ieee8021xclient_field private_key2_passwd "$private_key2_passwd"
		_ieee8021xclient_field dh_file2 "$dh_file2"
		_ieee8021xclient_field subject_match2 "$subject_match2"
		[ -n "$eap" ] && printf '\teap=%s\n' "$eap"
		[ -n "$eap_workaround" ] && printf '\teap_workaround=%s\n' "$eap_workaround"
		printf '}\n'
	} > "$_config" || {
		_ieee8021xclient_log "failed to write $_config (interface $cfg)"
		return 1
	}

	# 在较新的 OpenWrt (21.02+) 中，wpa_supplicant 并非以 root 运行，而是 network 用户。
	# 因此生成的配置文件必须允许 network 用户读取（644），否则会因 Permission denied 导致加载失败。
	chmod 644 "$_config" 2>/dev/null

	if ! ubus call wpa_supplicant config_add "{ \"driver\":\"wired\", \"iface\": \"$ifname\", \"config\": \"$_config\" }"; then
		# 只记录，不改变 netifd 状态机：让原有行为保持不变，但故障不再静默
		_ieee8021xclient_log "config_add failed (interface $cfg, device $ifname, config $_config); check wpa_supplicant state"
	fi
}

proto_ieee8021xclient_teardown() {
	local interface="$1"
	local ifname="$2"
	local errorstring=$(ieee8021xclient_exitcode_tostring $ERROR)

	# netifd 的 teardown 第二个参数才是设备名；缺失时回退到 setup 记录的映射，
	# 再不行才退回旧行为。传错名字会让 wpa_supplicant 里的接口残留，
	# 下一次 config_add 可能因此失败。
	[ -n "$ifname" ] || ifname=$(cat "/var/run/ieee8021xclient-$interface.ifname" 2>/dev/null)
	[ -n "$ifname" ] || ifname="$interface"

	case "$ERROR" in
		0)
		;;
		2)
			proto_notify_error "$interface" "$errorstring"
			proto_block_restart "$interface"
		;;
		*)
			proto_notify_error "$interface" "$errorstring"
		;;
	esac

	ubus call wpa_supplicant config_remove "{\"iface\":\"$ifname\"}"
	rm -f "/var/run/ieee8021xclient-$interface.ifname"
}

proto_ieee8021xclient_init_config() {
	proto_config_add_int eapol_version
	proto_config_add_string identity
	proto_config_add_string anonymous_identity
	proto_config_add_string password
	proto_config_add_string 'ca_cert:file'
	proto_config_add_string 'client_cert:file'
	proto_config_add_string 'private_key:file'
	proto_config_add_string private_key_passwd
	proto_config_add_string 'dh_file:file'
	proto_config_add_string subject_match
	proto_config_add_string phase1
	proto_config_add_string phase2
	proto_config_add_string 'ca_cert2:file'
	proto_config_add_string 'client_cert2:file'
	proto_config_add_string 'private_key2:file'
	proto_config_add_string private_key2_passwd
	proto_config_add_string 'dh_file2:file'
	proto_config_add_string subject_match2
	proto_config_add_string eap
	proto_config_add_boolean eap_workaround
}

[ -n "$INCLUDE_ONLY" ] || add_protocol ieee8021xclient
