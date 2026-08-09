#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

set -e

echo ">>> diy-part2.sh 开始"
echo "==> 开始执行 diy-part2.sh CPU和EN8811H修补流程..."

# =====================================================================
# 1. 注入 AN7581 CPUFreq 核心修复补丁 (解决 SMC 返回 0Hz 导致 cpufreq-dt 崩溃问题)
# =====================================================================
TARGET_PATCH_DIR="target/linux/airoha/patches-6.18"
mkdir -p "$TARGET_PATCH_DIR"

echo "==> 正在写入 CPU 调频 PLL Fallback 补丁..."
cat << 'EOF' > "$TARGET_PATCH_DIR/805-pmdomain-airoha-add-pll-register-fallback-for-cpu-clk.patch"
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: OpenWrt Builder
Date: Tue, 5 Aug 2026 21:10:00 +0000
Subject: [PATCH] pmdomain: airoha: add PLL register fallback for CPU clock rate

The CPU clock rate is obtained via an SMC call to BL31 (ARM Trusted
Firmware). When using the original manufacturer BL31 instead of the
OpenWrt custom BL31, this SMC call may return 0, causing cpufreq
initialization to fail with:
  cpufreq: cpufreq_policy_online: ->get() failed
  cpufreq-dt: failed register driver: -19

Add a fallback that reads the CPU PLL registers directly when the SMC
call returns 0.
---
 drivers/pmdomain/mediatek/airoha-cpu-pmdomain.c | 68 ++++++++++++++++++++++---
 1 file changed, 62 insertions(+), 6 deletions(-)

--- a/drivers/pmdomain/mediatek/airoha-cpu-pmdomain.c
+++ b/drivers/pmdomain/mediatek/airoha-cpu-pmdomain.c
@@ -3,6 +3,7 @@
 #include <linux/arm-smccc.h>
 #include <linux/bitfield.h>
 #include <linux/clk-provider.h>
+#include <linux/io.h>
 #include <linux/module.h>
 #include <linux/platform_device.h>
 #include <linux/pm_domain.h>
@@ -11,6 +12,14 @@
 #define AIROHA_SIP_AVS_HANDLE 0x82000301
 #define AIROHA_AVS_OP_BASE 0xddddddd0
 #define AIROHA_AVS_OP_MASK GENMASK(1, 0)
+
+/* CPU PLL registers for fallback when SMC is unavailable */
+#define AIROHA_CPU_PLL_BASE 0x1fa20000
+#define AIROHA_CPU_PLL_PCW_OFFSET 0x2b4
+#define AIROHA_CPU_PLL_CHG_OFFSET 0x2b8
+#define AIROHA_CPU_PLL_PCW_INT_MASK GENMASK(30, 24)
+#define AIROHA_CPU_PLL_POSDIV_MASK GENMASK(6, 4)
+
 #define AIROHA_AVS_OP_FREQ_DYN_ADJ (AIROHA_AVS_OP_BASE | \
  FIELD_PREP(AIROHA_AVS_OP_MASK, 0x1))
 #define AIROHA_AVS_OP_GET_FREQ (AIROHA_AVS_OP_BASE | \
@@ -19,6 +28,8 @@
 struct airoha_cpu_pmdomain_priv {
  struct clk_hw hw;
  struct generic_pm_domain pd;
+ void __iomem *pll_pcw;
+ void __iomem *pll_chg;
 };

 static int airoha_cpu_pmdomain_clk_determine_rate(struct clk_hw *hw,
@@ -30,13 +41,35 @@
 static unsigned long airoha_cpu_pmdomain_clk_get(struct clk_hw *hw,
  unsigned long parent_rate)
 {
+ struct airoha_cpu_pmdomain_priv *priv =
+ container_of(hw, struct airoha_cpu_pmdomain_priv, hw);
  struct arm_smccc_res res;
+ unsigned long freq;

  arm_smccc_1_1_invoke(AIROHA_SIP_AVS_HANDLE, AIROHA_AVS_OP_GET_FREQ,
        0, 0, 0, 0, 0, 0, &res);

  /* SMCCC returns freq in MHz */
- return (int)(res.a0 * 1000 * 1000);
+ freq = (unsigned long)(res.a0 * 1000 * 1000);
+
+ /* Fallback to PLL register read when SMC returns 0
+ * (e.g. original manufacturer BL31 doesn't support this SMC call)
+ */
+ if (freq == 0 && priv->pll_pcw && priv->pll_chg) {
+ u32 pcw_val = readl(priv->pll_pcw);
+ u32 chg_val = readl(priv->pll_chg);
+ u32 pcw_int = FIELD_GET(AIROHA_CPU_PLL_PCW_INT_MASK, pcw_val);
+ u32 posdiv = FIELD_GET(AIROHA_CPU_PLL_POSDIV_MASK, chg_val);
+
+ if (pcw_int > 0) {
+ if (posdiv == 0)
+ freq = pcw_int * 50 * 1000 * 1000;
+ else
+ freq = (pcw_int * 50 * 1000 * 1000) >> posdiv;
+ }
+ }
+
+ return freq;
 }

 /* Airoha CPU clk SMCC is always enabled */
@@ -80,6 +113,19 @@
  if (!priv)
  return -ENOMEM;

+ /* Map CPU PLL registers for fallback clock rate reading */
+ priv->pll_pcw = devm_ioremap(dev,
+      AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_PCW_OFFSET,
+      0x4);
+ priv->pll_chg = devm_ioremap(dev,
+      AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_CHG_OFFSET,
+      0x4);
+ if (!priv->pll_pcw || !priv->pll_chg) {
+ dev_warn(dev, "failed to map CPU PLL registers, SMC fallback disabled\n");
+ priv->pll_pcw = NULL;
+ priv->pll_chg = NULL;
+ }
+
  /* Init and register a get-only clk for Cpufreq */
  priv->hw.init = &init;
  ret = devm_clk_hw_register(dev, &priv->hw);
EOF
echo "✔ CPU 调频修复补丁注入完毕！"

# ============================================================
# 2. luci-app-airoha-npu（手动放入 + 修复路径）
# ============================================================
rm -rf package/luci-app-airoha-npu
git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-airoha-npu/Makefile
echo "✔ luci-app-airoha-npu 已放入并修复 Makefile"

# ============================================================
# 3. vlmcsd + luci-app-vlmcsd（使用 ImmortalWrt 源）
# ============================================================
rm -rf package/vlmcsd package/luci-app-vlmcsd /tmp/immortal-tmp
mkdir -p /tmp/immortal-tmp

git clone --depth=1 https://github.com/immortalwrt/packages.git /tmp/immortal-tmp/packages
git clone --depth=1 https://github.com/immortalwrt/luci.git /tmp/immortal-tmp/luci

cp -a /tmp/immortal-tmp/packages/net/vlmcsd package/vlmcsd
cp -a /tmp/immortal-tmp/luci/applications/luci-app-vlmcsd package/luci-app-vlmcsd

if [ -f package/luci-app-vlmcsd/Makefile ]; then
  sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-vlmcsd/Makefile 2>/dev/null || true
fi

rm -rf /tmp/immortal-tmp
echo "✔ ImmortalWrt 的 vlmcsd + luci-app-vlmcsd 已放入"

# ============================================================
# 4. 清理会导致 Kconfig 循环依赖的冲突包
# ============================================================
echo "==> 正在清理冲突包以修复 Kconfig 循环依赖报错..."
find feeds/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-fchomo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-momo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "momo" -exec rm -rf {} + 2>/dev/null || true
find package/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true
rm -rf feeds/helloworld/dae feeds/helloworld/daed
echo "✔ 冲突包清理完毕！"

# ============================================================
# 5. 第一次 defconfig
# ============================================================
make defconfig

# 安全净化设备标记
sed -i 's/CONFIG_TARGET_airoha_an7581_DEVICE_bell_xg-040g-md/CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md/g' .config 2>/dev/null || true

# ============================================================
# 6. 强制写入需要的包选项
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

# EN8811H PHY 驱动与 MD32 固件
CONFIG_PACKAGE_kmod-phy-airoha=y
CONFIG_PACKAGE_airoha-en8811h-firmware=y
CONFIG_PACKAGE_ethtool=y

# Devmem & Debug 支持
CONFIG_KERNEL_DEVMEM=y
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_DEVMEM=y
CONFIG_KERNEL_DEBUG_FS=y

# CPU 调频用户态与驱动模块
CONFIG_PACKAGE_kmod-cpufreq-dt=y
CONFIG_PACKAGE_kmod-cpufreq-governor-schedutil=y
CONFIG_PACKAGE_kmod-cpufreq-governor-performance=y
CONFIG_PACKAGE_kmod-cpufreq-governor-ondemand=y
CONFIG_PACKAGE_kmod-cpufreq-governor-conservative=y
EOF

make defconfig

# ============================================================
# 7. 再次强保关键包
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
  kmod-cpufreq-governor-schedutil \
  kmod-cpufreq-governor-performance \
  kmod-cpufreq-governor-ondemand \
  kmod-cpufreq-governor-conservative
do
  sed -i "s/# CONFIG_PACKAGE_${pkg} is not set/CONFIG_PACKAGE_${pkg}=y/" .config 2>/dev/null || true
  grep -q "CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# =====================================================================
# 8. 安全地在内核 config-* 中补充 CPUFreq 标志位 (添加安全换行，防语法破坏)
# =====================================================================
echo "==> 安全修补内核配置文件..."

find target/linux/airoha/ -name "config-*" -exec sed -i 's/CONFIG_STRICT_DEVMEM=y/# CONFIG_STRICT_DEVMEM is not set/g' {} +
find target/linux/airoha/ -name "config-*" -exec sed -i 's/CONFIG_IO_STRICT_DEVMEM=y/# CONFIG_IO_STRICT_DEVMEM is not set/g' {} +

for cfg in $(find target/linux/airoha/ -name "config-*"); do
    echo "修补内核配置文件: $cfg"
    # 确保文件末尾有独立换行，防止字符串拼接错误
    echo "" >> "$cfg"
    cat << 'EOF' >> "$cfg"
CONFIG_CPU_FREQ=y
CONFIG_CPU_FREQ_STAT=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_POWERSAVE=y
CONFIG_CPU_FREQ_GOV_USERSPACE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_THERMAL=y
CONFIG_ARM_CPUFREQ_DT=y
CONFIG_ARM_MEDIATEK_CPUFREQ=y
CONFIG_PM_OPP=y
# CONFIG_UCLAMP_TASK is not set
# CONFIG_UCLAMP_BUCKETS_COUNT is not set
CONFIG_ENERGY_MODEL=y
EOF
done

# =====================================================================
# 9. 自动修复 WAN MAC 地址 (来自 Commit 4e950b6 方案)
# =====================================================================
echo "==> 写入 WAN MAC 修复脚本 (99-fix-wan-mac)..."
mkdir -p target/linux/airoha/an7581/base-files/etc/uci-defaults/
cat << 'EOF' > target/linux/airoha/an7581/base-files/etc/uci-defaults/99-fix-wan-mac
#!/bin/sh
. /lib/functions.sh
BOARD=$(board_name)
case "$BOARD" in
nokia,xg-040g-md|\
nokia,xg-040g-md-ubi)
  WAN_MAC=$(uci get network.wan.macaddr 2>/dev/null)
  if [ -n "$WAN_MAC" ]; then
    logger -t "fix-wan-mac" "Clearing stale WAN MAC: $WAN_MAC"
    uci del network.wan.macaddr
    uci commit network
  fi
  rm -f /etc/uci-defaults/99-fix-wan-mac
  ;;
esac
exit 0
EOF
chmod +x target/linux/airoha/an7581/base-files/etc/uci-defaults/99-fix-wan-mac

# ============================================================
# 10. 最终检查
# ============================================================
echo ">>> 最终检查："
echo "--- 检查 CPU 调频内核补丁 ---"
if [ -f "$TARGET_PATCH_DIR/805-pmdomain-airoha-add-pll-register-fallback-for-cpu-clk.patch" ]; then
    echo "✔ 805-pmdomain 补丁就绪！"
else
    echo "❌ 警告：805-pmdomain 补丁丢失！"
fi

echo ">>> diy-part2.sh 执行完毕！"
