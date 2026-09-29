#!/bin/sh
#
# 在路由器上用自带的 apk mkpkg（apk-tools 3.x）生成 APKv3 包。
# 默认只打包、不安装，安装命令会打印出来供手动执行。
#
# 背景：OpenWrt / ImmortalWrt 25.12 起换成 apk-tools 3.x，只接受 APKv3 格式
# （文件头是 ADB 魔数的二进制 adb 格式），本地手工打的 v2（gzip tar）包装不上，
# 会报 "unexpected end of file"。用路由器自己的 mkpkg 打包最可靠。
#
# 用法：
#   sh /root/luci8021x/tools/build_apk_on_router.sh              # 只打包
#   sh /root/luci8021x/tools/build_apk_on_router.sh --install    # 打包并自动安装
#   sh /root/luci8021x/tools/build_apk_on_router.sh /某个/项目根  # 指定项目根目录
#
set -e

ARG_ROOT=""
DO_INSTALL=0
for _a in "$@"; do
	case "$_a" in
		--install|-i) DO_INSTALL=1 ;;
		*) ARG_ROOT="$_a" ;;
	esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

echo "== 环境 =="
apk --version 2>/dev/null || echo "  (apk --version 不可用)"
echo "  脚本目录: $SCRIPT_DIR"
echo "  系统 arch: $(cat /etc/apk/arch 2>/dev/null || echo '?')"
echo "  模式: $([ "$DO_INSTALL" = 1 ] && echo '打包并自动安装' || echo '只打包，不安装')"

# 在若干候选根目录下按相对路径找文件
locate() {
	_l_rel="$1"
	_l_flat="$2"
	for _l_root in "$ARG_ROOT" "$SCRIPT_DIR" "$SCRIPT_DIR/.." "$PWD" "/tmp"; do
		[ -n "$_l_root" ] || continue
		if [ -f "$_l_root/$_l_rel" ]; then echo "$_l_root/$_l_rel"; return 0; fi
		if [ -f "$_l_root/$_l_flat" ]; then echo "$_l_root/$_l_flat"; return 0; fi
	done
	return 1
}

PROG_SH=$(locate "net/ieee8021xclient/files/ieee8021xclient.sh" "ieee8021xclient.sh") || PROG_SH=""
PROG_JS=$(locate "luci-proto-ieee8021xclient/htdocs/luci-static/resources/protocol/ieee8021xclient.js" "ieee8021xclient.js") || PROG_JS=""

if [ -z "$PROG_SH" ] || [ -z "$PROG_JS" ]; then
	echo
	echo "找不到源文件。期望以下位置之一："
	echo "  <项目根>/net/ieee8021xclient/files/ieee8021xclient.sh"
	echo "  <项目根>/luci-proto-ieee8021xclient/htdocs/luci-static/resources/protocol/ieee8021xclient.js"
	echo "或把这两个文件直接放在 /tmp 下。已找到: sh='$PROG_SH' js='$PROG_JS'"
	exit 1
fi

echo "  协议脚本: $PROG_SH"
echo "  LuCI 脚本: $PROG_JS"

# busybox 里通常没有 install，统一用 mkdir/cp/chmod
put_file() {
	_p_src="$1"
	_p_dst="$2"
	_p_mode="$3"
	mkdir -p "$(dirname "$_p_dst")"
	cp "$_p_src" "$_p_dst"
	chmod "$_p_mode" "$_p_dst"
}

# 没装成功也没关系：把手动命令打印出来
MANUAL_PLAIN='mkdir -p /lib/netifd/proto /www/luci-static/resources/protocol
cp '"$PROG_SH"' /lib/netifd/proto/ieee8021xclient.sh
chmod 755 /lib/netifd/proto/ieee8021xclient.sh
cp '"$PROG_JS"' /www/luci-static/resources/protocol/ieee8021xclient.js
chmod 644 /www/luci-static/resources/protocol/ieee8021xclient.js
service network restart
rm -f /tmp/luci-indexcache*'

WORK=/tmp/apkv3build
rm -rf "$WORK"
mkdir -p "$WORK"

# ---- 1) ieee8021xclient ----
P1="$WORK/p1"
put_file "$PROG_SH" "$P1/lib/netifd/proto/ieee8021xclient.sh" 0755

if ! apk mkpkg -F "$P1" \
	-I name:ieee8021xclient \
	-I version:5-r0 \
	-I arch:noarch \
	-I description:"Wired 802.1x client config support" \
	-I license:GPL-2.0-or-later \
	-I origin:ieee8021xclient \
	-I maintainer:"David Yang <mmyangfl@gmail.com>" \
	-I url:https://github.com/openwrt/packages \
	-o "$WORK/ieee8021xclient-5-r0.apk"; then
	echo
	echo "!! apk mkpkg 调用失败（apk-tools < 3.x 或裁剪版）"
	echo "!! 无法打包，请手动放文件："
	echo "$MANUAL_PLAIN" | sed 's/^/  /'
	exit 1
fi

# ---- 2) luci-proto-ieee8021xclient ----
P2="$WORK/p2"
put_file "$PROG_JS" "$P2/www/luci-static/resources/protocol/ieee8021xclient.js" 0644

if ! apk mkpkg -F "$P2" \
	-I name:luci-proto-ieee8021xclient \
	-I version:1-r0 \
	-I arch:noarch \
	-I description:"LuCI support for the wired IEEE 802.1X client protocol" \
	-I license:GPL-2.0-or-later \
	-I origin:luci-proto-ieee8021xclient \
	-I maintainer:"David Yang <mmyangfl@gmail.com>" \
	-I url:https://github.com/openwrt/packages \
	-I depends:ieee8021xclient \
	-o "$WORK/luci-proto-ieee8021xclient-1-r0.apk"; then
	echo
	echo "!! 第二个包打包失败；第一个包已生成: $WORK/ieee8021xclient-5-r0.apk"
	exit 1
fi

echo
echo "== 打包完成 =="
ls -l "$WORK"/*.apk
echo "  文件头(应为 ADB): $(head -c 4 "$WORK/ieee8021xclient-5-r0.apk" | tr -d '\0')"

if [ "$DO_INSTALL" = 1 ]; then
	echo
	echo "== 安装 =="
	apk add --allow-untrusted --no-network \
		"$WORK/ieee8021xclient-5-r0.apk" \
		"$WORK/luci-proto-ieee8021xclient-1-r0.apk"
	service network restart
	rm -f /tmp/luci-indexcache*
	echo
	echo "已安装完成"
else
	echo
	echo "== 手动安装（复制执行即可）=="
	echo "apk add --allow-untrusted --no-network \\"
	echo "    $WORK/ieee8021xclient-5-r0.apk \\"
	echo "    $WORK/luci-proto-ieee8021xclient-1-r0.apk"
	echo "service network restart"
	echo "rm -f /tmp/luci-indexcache*"
fi

echo
echo "== 验证 =="
echo "  ls -l /lib/netifd/proto/ieee8021xclient.sh"
echo "  ls -l /www/luci-static/resources/protocol/ieee8021xclient.js"
echo "  ubus call network get_proto_handlers | grep -o ieee8021xclient"
