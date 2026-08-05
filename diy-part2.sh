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
# Derek 最终版（适用于 xiangtailiang 源码）
# 该源码已内置 NPU / LuCI / collectd / sensors / vlmcsd 补丁
# 所以不需要再 clone、补安全、禁用 safe-mode
# ============================================================

# 1. 删除旧残留包（可选）
rm -rf package/airoha-npu-firmware 2>/dev/null || true

# 2. 不再 clone luci-app-airoha-npu（源码已自带）
# 3. 不再 clone vlmcsd（源码已自带）
# 4. 不再 clone statistics（源码已自带）
# 5. 不再补安全（源码已自带）
# 6. 不再禁用 safe-mode（源码已自带修复）

# 7. 强制写入你需要的额外包（可选）
cat <<EOF >> .config
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_sing-box=y
EOF

# 8. 重新 defconfig
make defconfig

echo "✔ 使用 xiangtailiang 源码：已自动启用 NPU / LuCI / collectd / sensors / vlmcsd"
