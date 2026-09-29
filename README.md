# luci8021x

这是一个为 OpenWrt 提供基于底层网络守护进程（`netifd`）的 **原生的有线 IEEE 802.1X 客户端认证** 支持的插件项目。

通过此插件，你可以在 OpenWrt 的网络接口设置中，直接选择 `IEEE 802.1X Client` 协议对物理网口进行 EAP 认证（常用于校园网、企业网等环境）。

## 💡 特性

- **原生支持**：不使用后台定时脚本或魔改的外部程序，完全基于 OpenWrt 原生的 `netifd` + `wpa_supplicant` Ubus 总线通信，极其稳定，断线自动重连。
- **无缝集成**：完美集成于 LuCI 网页后台，只需像配置 PPPoE 一样简单地填入账号和密码。
- **兼容性广**：同时提供传统的 `.ipk` 安装包和适用于最新 ImmortalWrt / OpenWrt 25.12+ 架构的 `.apk` 安装包。

## 📥 下载与安装

进入项目的 [Releases 页面](https://github.com/M1s4k1/luci8021x/releases)，根据你的系统版本下载安装包：

- **OpenWrt 24.10 以前的版本（使用 opkg）**：
  下载 `ipk` 格式的包：
  - `ieee8021xclient_X-rX_all.ipk` (底层协议脚本)
  - `luci-proto-ieee8021xclient_X-rX_all.ipk` (LuCI 界面)
  
  上传到路由器后执行：
  ```bash
  opkg install ieee8021xclient_*.ipk luci-proto-ieee8021xclient_*.ipk
  ```

- **OpenWrt / ImmortalWrt 25.12 及更新版本（使用 apk）**：
  下载 `apk` 格式的包：
  - `ieee8021xclient-X-rX.apk` (底层协议脚本)
  - `luci-proto-ieee8021xclient-X-rX.apk` (LuCI 界面)
  
  上传到路由器后执行（若提示签名未信任可加 `--allow-untrusted`）：
  ```bash
  apk add --allow-untrusted ieee8021xclient-*.apk luci-proto-ieee8021xclient-*.apk
  ```

> **注意：** 安装过程中会自动触发 `/etc/init.d/network restart` 以加载新协议。如果不幸没有自动加载，请在网页手动重启路由器，或在终端输入 `/etc/init.d/network restart`。

## 🚀 使用方法

1. 登录路由器的 LuCI 管理页面，进入 **网络 -> 接口**。
2. 点击 **“添加新接口...” (Add new interface...)**。
3. **名称**：随意填写，例如 `wan_auth`。
4. **协议**：选择 **`IEEE 802.1X Client`**。
5. **设备**：选择你实际连接校园网/认证网络的**物理网口**（例如 `"wan" (wan, wan6)` 或 `eth1`）。请注意：**不能选择 `@` 开头的逻辑别名接口**，802.1X 必须工作在二层物理设备上。
6. 点击**提交**，在弹出的常规设置页面中，填入你的：
   - **EAP 方法**（如 `PEAP` 或 `TTLS`）
   - **认证用户名**（Identity）
   - **认证密码**（Password）
7. 切换到**高级设置**选项卡，如果有需要，可以填写 **阶段 2 选项 (Phase 2 options)**（如 `autheap=MSCHAPV2`）。
8. 点击 **“保存并应用”**。

认证成功后，该物理网口便会被上级交换机放行。此时，你可以让原本绑定在该物理网口上的 `wan` 接口通过 DHCP 或 PPPoE 正常获取 IP 并上网。
