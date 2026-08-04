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
#  Derek 最终整合版 diy-part2.sh（AN7581 专用）
#  - 手动创建 NPU 固件包（更好、更可控）
#  - LuCI NPU 监控界面
#  - vlmcsd + lm-sensors + LuCI 补安全
#  - 完全兼容 ImmortalWrt / OpenWrt
# ============================================================


# ============================================================
# 1. 删除 feeds 中的冲突包（避免覆盖）
# ============================================================
rm -rf package/vlmcsd package/luci-app-vlmcsd package/vlmcsd-tmp
rm -rf package/luci-app-statistics package/luci-app-statistics-tmp
rm -rf package/airoha-npu-firmware package/luci-app-airoha-npu


# ============================================================
# 2. 创建 NPU 固件包（来自 openwrt/target/linux/airoha）
# ============================================================
mkdir -p package/airoha-npu-firmware/files/lib/firmware/airoha

# 复制官方固件（你必须已 clone openwrt 主仓库）
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


# ============================================================
# 3. 拉取 LuCI NPU 监控界面（第三方）
# ============================================================
git clone https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu


# ============================================================
# 4. 拉取 vlmcsd（来自 ImmortalWrt packages）
# ============================================================
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp


# ============================================================
# 5. 拉取 luci-app-vlmcsd（来自 ImmortalWrt luci）
# ============================================================
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set applications/luci-app-vlmcsd
cd ../..
mv package/vlmcsd-tmp/applications/luci-app-vlmcsd package/luci-app-vlmcsd
rm -rf package/vlmcsd-tmp


# ============================================================
# 6. 补安全：解除 AN7581 对 vlmcsd LuCI 的裁剪
# ============================================================
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' package/luci-app-vlmcsd/Makefile


# ============================================================
# 7. 补安全：解除 AN7581 对 lm-sensors LuCI 的裁剪
# ============================================================
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +libpthread/' feeds/luci/applications/luci-app-statistics/Makefile


# ============================================================
# 8. 强制写入 .config（确保一定编译）
# ============================================================
cat <<EOF >> .config
CONFIG_PACKAGE_airoha-npu-firmware=y
CONFIG_PACKAGE_luci-app-airoha-npu=y

CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y

CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_luci-app-statistics=y
CONFIG_PACKAGE_collectd-mod-sensors=y
EOF


# ============================================================
# 9. 重新 defconfig（必须）
# ============================================================
make defconfig

echo "✔ 最终整合版已完成：NPU + vlmcsd + lm-sensors + LuCI 补安全全部启用"
