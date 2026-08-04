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

#!/bin/bash

# ============================================================
#  Derek 最终版：主线 NPU + LuCI NPU + 补安全
# ============================================================

# -------------------------------
# 1. 删除冲突包（避免覆盖）
# -------------------------------
rm -rf package/luci-app-airoha-npu

# -------------------------------
# 2. 拉取 LuCI NPU 监控界面（第三方）
# -------------------------------
git clone https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# -------------------------------
# 3. LuCI NPU 依赖：collectd
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_collectd=y
CONFIG_PACKAGE_collectd-mod-exec=y
CONFIG_PACKAGE_collectd-mod-sensors=y
CONFIG_PACKAGE_collectd-mod-cpu=y
CONFIG_PACKAGE_collectd-mod-interface=y
EOF

# -------------------------------
# 4. 补安全：解除 AN7581 对 LuCI 的裁剪
# -------------------------------
# 解除对 NPU LuCI 的裁剪
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-airoha-npu/Makefile

# 解除对 vlmcsd 的裁剪
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-vlmcsd/Makefile

# 解除对 lm-sensors 的裁剪
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' feeds/luci/applications/luci-app-statistics/Makefile

# -------------------------------
# 5. 强制写入 .config（确保一定编译）
# -------------------------------
cat <<EOF >> .config
# 主线 NPU 固件（自动启用）
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y

# LuCI NPU 页面
CONFIG_PACKAGE_luci-app-airoha-npu=y

# vlmcsd
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y

# lm-sensors
CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_luci-app-statistics=y
EOF

# -------------------------------
# 6. 重新 defconfig
# -------------------------------
make defconfig

echo "✔ 主线 NPU + LuCI NPU + 补安全 已全部启用"
