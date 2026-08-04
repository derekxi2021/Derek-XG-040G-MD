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

# -------------------------------
# 拉取 luci-app-airoha-npu
# -------------------------------
rm -rf package/luci-app-airoha-npu package/airoha-tmp
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/airoha-tmp
cd package/airoha-tmp
git sparse-checkout set applications/luci-app-airoha-npu
cd ../..
mv package/airoha-tmp/applications/luci-app-airoha-npu package/luci-app-airoha-npu
rm -rf package/airoha-tmp

# -------------------------------
# 拉取 airoha-npu-firmware（关键）
# -------------------------------
rm -rf package/airoha-npu-firmware package/airoha-npu-fw-tmp
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/airoha-npu-fw-tmp
cd package/airoha-npu-fw-tmp
git sparse-checkout set firmware/airoha-npu-firmware
cd ../..
mv package/airoha-npu-fw-tmp/firmware/airoha-npu-firmware package/airoha-npu-firmware
rm -rf package/airoha-npu-fw-tmp

# -------------------------------
#  强制写入 .config（确保一定编译）
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_airoha-npu-firmware=y
CONFIG_PACKAGE_luci-app-airoha-npu=y
EOF


# -------------------------------
#  拉取 vlmcsd（不会被 feeds 覆盖）
# -------------------------------
rm -rf package/vlmcsd package/luci-app-vlmcsd package/vlmcsd-tmp

git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp

git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set applications/luci-app-vlmcsd
cd ../..
mv package/vlmcsd-tmp/applications/luci-app-vlmcsd package/luci-app-vlmcsd
rm -rf package/vlmcsd-tmp

# -------------------------------
#  强制写入 .config（关键步骤）
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
EOF
