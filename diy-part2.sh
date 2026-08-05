#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# ============================================================
# 针对 xiangtailiang/openwrt + AN7581 (Nokia/Bell XG-040G-MD)
# 强制编译进：NPU固件 + luci-app-airoha-npu + luci-app-vlmcsd
# ============================================================

echo ">>> 开始执行 diy-part2.sh"

# 1. 清理可能冲突的旧目录
rm -rf package/luci-app-airoha-npu 2>/dev/null || true
rm -rf package/airoha-npu-firmware 2>/dev/null || true

# 2. 手动克隆 luci-app-airoha-npu（第三方包，必须放进 package/）
echo ">>> 克隆 luci-app-airoha-npu ..."
git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# 3. 确保 kenzo 源里的 vlmcsd 相关包被安装
echo ">>> 安装 vlmcsd 相关包 ..."
./scripts/feeds install -a -p kenzo 2>/dev/null || true
./scripts/feeds install luci-app-vlmcsd vlmcsd 2>/dev/null || true

# 4. 先执行一次 defconfig，让目标设备配置生效
echo ">>> 执行 make defconfig (第一次) ..."
make defconfig

# 5. 强制写入需要的包（必须放在 make defconfig 之后！）
echo ">>> 强制写入关键包到 .config ..."
cat <<EOF >> .config

# ---------- NPU 相关 ----------
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y
CONFIG_PACKAGE_kmod-airoha-npu=y
CONFIG_PACKAGE_luci-app-airoha-npu=y
CONFIG_PACKAGE_luci-i18n-airoha-npu-zh-cn=y

# ---------- VLMCSD ----------
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y

# ---------- 其他你需要的（可按需增减）----------
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_sing-box=y
EOF

# 6. 再次 defconfig，让刚写入的配置生效
echo ">>> 执行 make defconfig (第二次) ..."
make defconfig

# 7. 最终验证（方便在 Actions 日志中查看）
echo "========== 最终 .config 检查 =========="
grep -E "CONFIG_PACKAGE_airoha-en7581-npu-firmware=y|CONFIG_PACKAGE_luci-app-airoha-npu=y|CONFIG_PACKAGE_luci-app-vlmcsd=y|CONFIG_PACKAGE_kmod-airoha-npu=y" .config || echo "⚠️ 警告：部分包仍未选中！"
echo "======================================"

echo ">>> diy-part2.sh 执行完毕"
