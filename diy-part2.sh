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
#  Derek 最终版：主线 NPU + LuCI NPU + collectd + 补安全
# ============================================================

# -------------------------------
# 1. 删除冲突包（避免覆盖）
# -------------------------------
rm -rf package/luci-app-airoha-npu
rm -rf package/luci-app-vlmcsd
rm -rf package/vlmcsd
rm -rf package/luci-app-statistics

# -------------------------------
# 2. 拉取 LuCI NPU 监控界面（第三方）
# -------------------------------
git clone https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# -------------------------------
# 3. 拉取 vlmcsd（ImmortalWrt packages）
# -------------------------------
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp

# -------------------------------
# 4. 拉取 luci-app-vlmcsd（ImmortalWrt luci）
# -------------------------------
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/vlmcsd-luci-tmp
cd package/vlmcsd-luci-tmp
git sparse-checkout set applications/luci-app-vlmcsd
cd ../..
mv package/vlmcsd-luci-tmp/applications/luci-app-vlmcsd package/luci-app-vlmcsd
rm -rf package/vlmcsd-luci-tmp

# -------------------------------
# 5. 拉取 luci-app-statistics（lm-sensors 的 LuCI）
# -------------------------------
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/statistics-luci-tmp
cd package/statistics-luci-tmp
git sparse-checkout set applications/luci-app-statistics
cd ../..
mv package/statistics-luci-tmp/applications/luci-app-statistics package/luci-app-statistics
rm -rf package/statistics-luci-tmp

# -------------------------------
# 6. LuCI NPU 依赖：collectd
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_collectd=y
CONFIG_PACKAGE_collectd-mod-exec=y
CONFIG_PACKAGE_collectd-mod-sensors=y
CONFIG_PACKAGE_collectd-mod-cpu=y
CONFIG_PACKAGE_collectd-mod-interface=y
EOF

# -------------------------------
# 7. 补安全：解除 AN7581 对 LuCI 的裁剪
# -------------------------------
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-airoha-npu/Makefile
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-vlmcsd/Makefile
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-statistics/Makefile

# -------------------------------
# 8. 强制写入 .config（确保一定编译）
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y
CONFIG_PACKAGE_luci-app-airoha-npu=y
CONFIG_PACKAGE_luci-i18n-airoha-npu-zh-cn=y

CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y

CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_luci-app-statistics=y
EOF

# -------------------------------
# 9. 重新 defconfig
# -------------------------------
make defconfig

echo "✔ 主线 NPU + LuCI NPU + collectd + 补安全 已全部启用"
