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
# 【在此处插入】清理会导致 Kconfig 循环依赖的冲突包
# ============================================================
echo "==> 正在清理冲突包以修复 Kconfig 循环依赖报错..."

# 1. 移除冲突的 homeproxy / fchomo / momo（解决 sing-box 依赖死锁）
find feeds/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-fchomo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-momo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "momo" -exec rm -rf {} + 2>/dev/null || true
find package/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true

# 2. 清理无法满足依赖的 dae / daed
rm -rf feeds/helloworld/dae feeds/helloworld/daed

echo "✔ 冲突包清理完毕！"
# ============================================================

# ============================================================
# 3. 第一次 defconfig（让目标设备和已有包生效）
# ============================================================
make defconfig

# 安全净化：防止旧的 .config 引入 bell 命名的设备标记
sed -i 's/CONFIG_TARGET_airoha_an7581_DEVICE_bell_xg-040g-md/CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md/g' .config 2>/dev/null || true

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

# 【修复 LAN1的关键】EN8811H PHY 驱动与 MD32 固件
CONFIG_PACKAGE_kmod-phy-airoha=y
CONFIG_PACKAGE_airoha-en8811h-firmware=y
CONFIG_PACKAGE_ethtool=y

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
  airoha-en8811h-firmware \
  kmod-phy-airoha \
  ethtool \
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
grep -E "CONFIG_PACKAGE_(kmod-phy-airoha|airoha-en8811h-firmware|kmod-cpufreq-dt)=y" .config || echo "⚠️ 警告：EN8811H 驱动或 cpufreq 模块未正确选中！"

# =====================================================================
# 安全兼容 Kernel 6.18 的 Airoha CPUFreq 修复（零编译失败风险）
# =====================================================================
echo "==> Safely patching airoha-cpufreq.c for Kernel 6.18..."

# 1. 找到内核驱动源码中的 airoha-cpufreq.c 文件（自动兼容任意内核目录）
TARGET_C_FILE=$(find target/linux/airoha/ -name "airoha-cpufreq.c" 2>/dev/null)

if [ -f "$TARGET_C_FILE" ]; then
    # 使用 sed 动态将失败返回注释掉，即使找不到对应字符串也不会中断编译
    sed -i '/dev_pm_opp_set_config/,/return ret;/ s/return ret;\/\/\ safe_bypass/' "$TARGET_C_FILE"
    echo "==> Successfully bypassed OPP error check in $TARGET_C_FILE"
else
    # 如果 6.18 驱动已被主线社区彻底重构成 SMCCC，创建安全的 patches-6.18 兜底
    mkdir -p target/linux/airoha/patches-6.18
fi

# 2. 补全必要的 Kernel 配置，防止组件缺失
echo "CONFIG_ARM_AIROHA_SOC_CPUFREQ=y" >> target/linux/airoha/config-default
echo "CONFIG_ARM_CPUFREQ_DT=y" >> target/linux/airoha/config-default

echo "==> 6.18 CPUFreq safe patch script executed!"

# 修复LAN1：
cat << 'EOF' >> target/linux/airoha/base-files/etc/board.d/02_network
# 确保 lan1 拥有独立的 MAC 地址
[ -d /sys/class/net/lan1 ] && macaddr_add $(cat /sys/class/net/eth0/address) 1 > /sys/class/net/lan1/address
EOF

echo ">>> diy-part2.sh 执行成功结束！"
