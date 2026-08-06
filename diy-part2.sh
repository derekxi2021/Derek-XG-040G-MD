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

set -e

echo ">>> diy-part2.sh 开始"

echo "==> 开始执行 diy-part2.sh CPU和EN8811H修补流程..."

# -----------------------------------------------------------------
# 1. 自动清理可能存在的冲突补丁（防止重复打补丁导致编译失败）
# -----------------------------------------------------------------
TARGET_PATCH_DIR="target/linux/airoha/patches-6.18"
if [ -d "$TARGET_PATCH_DIR" ]; then
    echo "==> 正在清理可能导致冲突的重复 cpufreq / pmdomain 补丁..."
    rm -f $TARGET_PATCH_DIR/*cpufreq*.patch
    rm -f $TARGET_PATCH_DIR/*pmdomain*.patch
fi

# -----------------------------------------------------------------
# 2. 追加内核原生参数到 Airoha 平台的 Target Kernel Config (激活 cpufreq 支持)
# -----------------------------------------------------------------
TARGET_KERNEL_CONFIG="target/linux/airoha/config-6.18"
if [ -f "$TARGET_KERNEL_CONFIG" ]; then
    echo "==> 正在追加 cpufreq 内核参数到 $TARGET_KERNEL_CONFIG ..."
    cat << EOF >> $TARGET_KERNEL_CONFIG
CONFIG_CPU_FREQ=y
CONFIG_CPU_FREQ_STAT=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y
EOF
fi

# -----------------------------------------------------------------
# 3. 修复 EN8811H 2.5G 网口速率协商缺陷 (2500base-x -> usxgmii)
# -----------------------------------------------------------------
DTS_FILE=$(find target/linux/airoha/ -name "*xg-040g-md*.dts" 2>/dev/null)

if [ -n "$DTS_FILE" ]; then
    echo "==> 找到设备树文件: $DTS_FILE"
    echo "==> 正在修复 EN8811H phy-mode 配置..."
    sed -i 's/phy-mode = "2500base-x";/phy-mode = "usxgmii";/g' $DTS_FILE
else
    echo "==> 提示: 未在 target/linux/airoha 中检索到 xg-040g-md DTS，跳过 DTS 修改。"
fi

# -----------------------------------------------------------------
# 4. 追加根目录 .config 软件包与 devmem / cpufreq 选项
# -----------------------------------------------------------------
echo "==> 追加 OpenWrt 软件包与 Busybox devmem 配置到 .config ..."
cat << EOF >> .config

# Devmem & Debug 支持
CONFIG_KERNEL_DEVMEM=y
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_DEVMEM=y
CONFIG_KERNEL_DEBUG_FS=y

# CPU 调频 kmod 驱动与策略
CONFIG_PACKAGE_kmod-cpufreq-dt=y
CONFIG_PACKAGE_kmod-cpufreq-governor-performance=y
CONFIG_PACKAGE_kmod-cpufreq-governor-ondemand=y
CONFIG_PACKAGE_kmod-cpufreq-governor-conservative=y
EOF

echo "==> diy-part2.sh CPU和EN8811H修补流程执行完毕！"

# ============================================================
# 1. luci-app-airoha-npu（官方没有，必须手动放 + 修复路径）
# ============================================================
rm -rf package/luci-app-airoha-npu
git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# 关键：修复 Makefile 里错误的相对路径
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-airoha-npu/Makefile

echo "✔ luci-app-airoha-npu 已放入并修复 Makefile"

# ============================================================
# 2. vlmcsd + luci-app-vlmcsd（使用 ImmortalWrt 源）
# ============================================================
rm -rf package/vlmcsd package/luci-app-vlmcsd /tmp/immortal-tmp
mkdir -p /tmp/immortal-tmp

git clone --depth=1 https://github.com/immortalwrt/packages.git /tmp/immortal-tmp/packages
git clone --depth=1 https://github.com/immortalwrt/luci.git /tmp/immortal-tmp/luci

cp -a /tmp/immortal-tmp/packages/net/vlmcsd package/vlmcsd
cp -a /tmp/immortal-tmp/luci/applications/luci-app-vlmcsd package/luci-app-vlmcsd

# 修复可能的 luci.mk 路径
if [ -f package/luci-app-vlmcsd/Makefile ]; then
  sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-vlmcsd/Makefile 2>/dev/null || true
fi

rm -rf /tmp/immortal-tmp
echo "✔ ImmortalWrt 的 vlmcsd + luci-app-vlmcsd 已放入"

# ============================================================
# 3. 第一次 defconfig（让目标设备和已有包生效）
# ============================================================
make defconfig

# ============================================================
# 4. 强制写入需要的包
# ============================================================
cat << 'EOF' >> .config
# NPU & 核心 App
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y
CONFIG_PACKAGE_luci-app-airoha-npu=y
CONFIG_PACKAGE_luci-i18n-airoha-npu-zh-cn=y
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_sing-box=y

# Devmem & Debug 支持
CONFIG_KERNEL_DEVMEM=y
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_DEVMEM=y
CONFIG_KERNEL_DEBUG_FS=y

# CPU 调频 kmod 模块
CONFIG_PACKAGE_kmod-cpufreq-dt=y
CONFIG_PACKAGE_kmod-cpufreq-governor-performance=y
CONFIG_PACKAGE_kmod-cpufreq-governor-ondemand=y
CONFIG_PACKAGE_kmod-cpufreq-governor-conservative=y
EOF

make defconfig

# ============================================================
# 5. 再次强制保住（防止被 defconfig 取消）
# ============================================================
for pkg in \
  airoha-en7581-npu-firmware \
  luci-app-airoha-npu \
  luci-i18n-airoha-npu-zh-cn \
  vlmcsd \
  luci-app-vlmcsd \
  luci-i18n-vlmcsd-zh-cn \
  kmod-cpufreq-dt \
  kmod-cpufreq-governor-performance \
  kmod-cpufreq-governor-ondemand \
  kmod-cpufreq-governor-conservative
do
  sed -i "s/# CONFIG_PACKAGE_${pkg} is not set/CONFIG_PACKAGE_${pkg}=y/" .config 2>/dev/null || true
  grep -q "CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# ============================================================
# 6. 最终检查
# ============================================================
echo ">>> 最终检查："
echo "--- 目录是否存在 ---"
ls -d package/luci-app-airoha-npu package/vlmcsd package/luci-app-vlmcsd 2>/dev/null || echo "⚠️ 有目录缺失"

echo "--- .config 关键选项 ---"
grep -E "CONFIG_PACKAGE_(airoha-en7581-npu-firmware|luci-app-airoha-npu|vlmcsd|luci-app-vlmcsd|kmod-cpufreq-dt)=y" .config || echo "⚠️ 有包未选中"

echo ">>> diy-part2.sh 执行成功结束！"
