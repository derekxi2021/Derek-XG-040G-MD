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
#  AN7581 / EN7581 NPU 正确拉取方式（最终版）
# ============================================================

# -------------------------------
# 1. 拉取官方 NPU 固件（来自 openwrt.git）
# -------------------------------
rm -rf package/airoha-npu-firmware
mkdir -p package/airoha-npu-firmware/files/lib/firmware/airoha

# 复制官方固件（你必须把 openwrt 主仓库 clone 下来）
cp -r target/linux/airoha/files/lib/firmware/airoha/* \
      package/airoha-npu-firmware/files/lib/firmware/airoha/

cat <<EOF > package/airoha-npu-firmware/Makefile
include \$(TOPDIR)/rules.mk

PKG_NAME:=airoha-npu-firmware
PKG_VERSION:=1.0
PKG_RELEASE:=1

include \$(INCLUDE_DIR)/package.mk

define Package/airoha-npu-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Airoha EN7581 NPU Firmware
endef

define Package/airoha-npu-firmware/install
    \$(INSTALL_DIR) \$(1)/lib/firmware/airoha
    \$(CP) ./files/lib/firmware/airoha/* \$(1)/lib/firmware/airoha/
endef

\$(eval \$(call BuildPackage,airoha-npu-firmware))
EOF

# -------------------------------
# 2. 拉取 LuCI NPU 监控界面（第三方）
# -------------------------------
rm -rf package/luci-app-airoha-npu
git clone https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# -------------------------------
# 3. 强制写入 .config
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_airoha-npu-firmware=y
CONFIG_PACKAGE_luci-app-airoha-npu=y
EOF

# -------------------------------
#  拉取 vlmcsd（不会被 feeds 覆盖）
# -------------------------------

# -------------------------------
# 1. 删除 feeds 中的 vlmcsd，避免覆盖
# -------------------------------
rm -rf package/vlmcsd package/luci-app-vlmcsd package/vlmcsd-tmp

# -------------------------------
# 2. 拉取 vlmcsd（来自 ImmortalWrt）
# -------------------------------
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp

# -------------------------------
# 3. 拉取 luci-app-vlmcsd（来自 ImmortalWrt）
# -------------------------------
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set applications/luci-app-vlmcsd
cd ../..
mv package/vlmcsd-tmp/applications/luci-app-vlmcsd package/luci-app-vlmcsd
rm -rf package/vlmcsd-tmp

# -------------------------------
# 4. 强制写入 .config（关键步骤）
# -------------------------------
cat <<EOF >> .config
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
EOF

# -------------------------------
# 5. AN7581 平台补安全（必须）
#    否则 vlmcsd 会被安全裁剪机制过滤掉
# -------------------------------
sed -i '/Package\/vlmcsd/,+5 s/DEPENDS:=.*/DEPENDS:=+libpthread/' package/vlmcsd/Makefile

# -------------------------------
# 6. 再次执行 defconfig（必须）
# -------------------------------
make defconfig

echo "✔ vlmcsd 已强制启用并补安全，AN7581 平台不会再过滤掉。"
