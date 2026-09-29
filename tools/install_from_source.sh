#!/bin/sh
#
# 从项目源码目录直接安装到路由器（不经过包管理器，不需要 apk/ipk）。
#
# 说明：ieee8021xclient.sh 是 netifd 的协议处理器，不能被"直接执行"——
# 它第 6 行用相对路径 `. ../netifd-proto.sh` 依赖自己位于 /lib/netifd/proto/，
# 且真正工作的参数由 netifd 传入。必须放到 /lib/netifd/proto/ 并由 netifd 调用。
#
# 用法：把整个 luci8021x 目录放到路由器（比如 /root/luci8021x），然后
#   sh /root/luci8021x/tools/install_from_source.sh
# 或指定目录：
#   sh /root/luci8021x/tools/install_from_source.sh /root/luci8021x
#
set -e

REPO="${1:-$(dirname "$(dirname "$0")")}"

SH_SRC="$REPO/net/ieee8021xclient/files/ieee8021xclient.sh"
JS_SRC="$REPO/luci-proto-ieee8021xclient/htdocs/luci-static/resources/protocol/ieee8021xclient.js"

for f in "$SH_SRC" "$JS_SRC"; do
	[ -f "$f" ] || { echo "找不到源文件: $f"; exit 1; }
done

echo "项目目录: $REPO"

# ---- 1) netifd 协议处理器 ----
install -d /lib/netifd/proto
install -m 0755 "$SH_SRC" /lib/netifd/proto/ieee8021xclient.sh
echo "已安装 /lib/netifd/proto/ieee8021xclient.sh"

# ---- 2) LuCI 协议表单 ----
install -d /www/luci-static/resources/protocol
install -m 0644 "$JS_SRC" /www/luci-static/resources/protocol/ieee8021xclient.js
echo "已安装 /www/luci-static/resources/protocol/ieee8021xclient.js"

# ---- 3) 重启 netifd 让它加载新协议 ----
service network restart
rm -f /tmp/luci-indexcache*

# ---- 4) 验证 ----
echo
echo "== 验证 =="
if ubus call network get_proto_handlers 2>/dev/null | grep -q ieee8021xclient; then
	echo "  [OK] netifd 已识别协议 ieee8021xclient"
else
	echo "  [!!] ubus 里还没看到 ieee8021xclient，请检查："
	echo "       sh -n /lib/netifd/proto/ieee8021xclient.sh"
	echo "       logread | tail -30"
fi

echo
echo "== 下一步：加认证接口（不要改 wan 的 proto） =="
echo "  uci set network.wan_auth=interface"
echo "  uci set network.wan_auth.device='wan'"
echo "  uci set network.wan_auth.proto='ieee8021xclient'"
echo "  uci set network.wan_auth.eap='PEAP'"
echo "  uci set network.wan_auth.identity='你的账号'"
echo "  uci set network.wan_auth.password='你的密码'"
echo "  uci set network.wan_auth.phase2='auth=MSCHAPV2'"
echo "  uci commit network && service network reload"
