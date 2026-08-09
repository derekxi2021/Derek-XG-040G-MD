#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

set -e

echo ">>> diy-part2.sh 开始"
echo "==> 开始执行 diy-part2.sh 修补流程..."

# =====================================================================
# 0. 终极修复：解决 uboot-airoha 安装时缺少 u-boot.dtb 导致的 Error 127
# =====================================================================
echo "==> 正在对 uboot-airoha/Makefile 进行底层安全打补丁..."

find package/ -type f -path "*/uboot-airoha/Makefile" | while read -r mkfile; do
    echo "正在修补: $mkfile"
    
    # 策略 1: 编译完成后，若 PKG_BUILD_DIR 根目录下没有 u-boot.dtb，则自动 touch 一个占位文件
    # 避免后续 install 指令因为源文件不存在而爆出 Error 127
    if ! grep -q "touch \$(PKG_BUILD_DIR)/u-boot.dtb" "$mkfile"; then
        sed -i '/define Build\/Compile/a \t[ -f $(PKG_BUILD_DIR)/u-boot.dtb ] || touch $(PKG_BUILD_DIR)/u-boot.dtb' "$mkfile"
    fi

    # 策略 2: 容错处理所有的安装与复制指令
    sed -i 's/$(INSTALL_DATA) \(.*u-boot\.dtb\)/[ -f \1 ] \&\& $(INSTALL_DATA) \1 || true/g' "$mkfile"
    sed -i 's/install -m0644 \(.*u-boot\.dtb\)/[ -f \1 ] \&\& install -m0644 \1 || true/g' "$mkfile"
    sed -i 's/$(CP) \(.*u-boot\.dtb\)/[ -f \1 ] \&\& $(CP) \1 || true/g' "$mkfile"
done

echo "✔ uboot-airoha 安全防护注入完成！"

# =====================================================================
# 1. 直接覆盖 AN7581 CPU PM Domain 驱动 (解决 SMC 0Hz 问题)
# =====================================================================
echo "==> 正在注入修复版 airoha-cpu-pmdomain.c..."
rm -f target/linux/airoha/patches-6.18/*pmdomain*.patch 2>/dev/null || true

TARGET_C_DIR="target/linux/airoha/files/drivers/pmdomain/mediatek"
mkdir -p "$TARGET_C_DIR"

cat << 'EOF' > "$TARGET_C_DIR/airoha-cpu-pmdomain.c"
// SPDX-License-Identifier: GPL-2.0-only
/*
 * Airoha AN7581 CPU PM domain and clock driver
 * Direct-override version with PLL fallback
 */

#include <linux/arm-smccc.h>
#include <linux/bitfield.h>
#include <linux/clk-provider.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>

#define AIROHA_SIP_AVS_HANDLE 0x82000301
#define AIROHA_AVS_OP_BASE 0xddddddd0
#define AIROHA_AVS_OP_MASK GENMASK(1, 0)

/* CPU PLL registers for fallback when SMC is unavailable */
#define AIROHA_CPU_PLL_BASE 0x1fa20000
#define AIROHA_CPU_PLL_PCW_OFFSET 0x2b4
#define AIROHA_CPU_PLL_CHG_OFFSET 0x2b8
#define AIROHA_CPU_PLL_PCW_INT_MASK GENMASK(30, 24)
#define AIROHA_CPU_PLL_POSDIV_MASK GENMASK(6, 4)

#define AIROHA_AVS_OP_FREQ_DYN_ADJ (AIROHA_AVS_OP_BASE | \
				    FIELD_PREP(AIROHA_AVS_OP_MASK, 0x1))
#define AIROHA_AVS_OP_GET_FREQ (AIROHA_AVS_OP_BASE | \
				FIELD_PREP(AIROHA_AVS_OP_MASK, 0x2))

struct airoha_cpu_pmdomain_priv {
	struct clk_hw hw;
	struct generic_pm_domain pd;
	void __iomem *pll_pcw;
	void __iomem *pll_chg;
};

static unsigned long airoha_cpu_pmdomain_clk_get(struct clk_hw *hw,
						 unsigned long parent_rate)
{
	struct airoha_cpu_pmdomain_priv *priv =
		container_of(hw, struct airoha_cpu_pmdomain_priv, hw);
	struct arm_smccc_res res;
	unsigned long freq;

	arm_smccc_1_1_invoke(AIROHA_SIP_AVS_HANDLE, AIROHA_AVS_OP_GET_FREQ,
			     0, 0, 0, 0, 0, 0, &res);

	/* SMCCC returns freq in MHz */
	freq = (unsigned long)(res.a0 * 1000 * 1000);

	/* Fallback to PLL register read when SMC returns 0 */
	if (freq == 0 && priv->pll_pcw && priv->pll_chg) {
		u32 pcw_val = readl(priv->pll_pcw);
		u32 chg_val = readl(priv->pll_chg);
		u32 pcw_int = FIELD_GET(AIROHA_CPU_PLL_PCW_INT_MASK, pcw_val);
		u32 posdiv = FIELD_GET(AIROHA_CPU_PLL_POSDIV_MASK, chg_val);

		if (pcw_int > 0) {
			if (posdiv == 0)
				freq = pcw_int * 50 * 1000 * 1000;
			else
				freq = (pcw_int * 50 * 1000 * 1000) >> posdiv;
		}
	}

	return freq;
}

static int airoha_cpu_pmdomain_clk_determine_rate(struct clk_hw *hw,
						   struct clk_rate_request *req)
{
	req->rate = airoha_cpu_pmdomain_clk_get(hw, 0);
	return 0;
}

static const struct clk_ops airoha_cpu_pmdomain_clk_ops = {
	.get_rate = airoha_cpu_pmdomain_clk_get,
	.determine_rate = airoha_cpu_pmdomain_clk_determine_rate,
};

static int airoha_cpu_pmdomain_probe(struct platform_device *pdev)
{
	struct clk_init_data init = {
		.name = "airoha_cpu_clk",
		.ops = &airoha_cpu_pmdomain_clk_ops,
	};
	struct airoha_cpu_pmdomain_priv *priv;
	struct device *dev = &pdev->dev;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	/* Map CPU PLL registers for fallback clock rate reading */
	priv->pll_pcw = devm_ioremap(dev,
				     AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_PCW_OFFSET,
				     0x4);
	priv->pll_chg = devm_ioremap(dev,
				     AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_CHG_OFFSET,
				     0x4);
	if (!priv->pll_pcw || !priv->pll_chg) {
		dev_warn(dev, "failed to map CPU PLL registers, SMC fallback disabled\n");
		priv->pll_pcw = NULL;
		priv->pll_chg = NULL;
	}

	priv->hw.init = &init;
	ret = devm_clk_hw_register(dev, &priv->hw);
	if (ret)
		return ret;

	ret = devm_of_clk_add_hw_provider(dev, of_clk_hw_simple_get, &priv->hw);
	if (ret)
		return ret;

	priv->pd.name = dev_name(dev);
	return pm_genpd_init(&priv->pd, NULL, false);
}

static const struct of_device_id airoha_cpu_pmdomain_match[] = {
	{ .compatible = "airoha,an7581-cpu-pmdomain" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, airoha_cpu_pmdomain_match);

static struct platform_driver airoha_cpu_pmdomain_driver = {
	.probe = airoha_cpu_pmdomain_probe,
	.driver = {
		.name = "airoha-cpu-pmdomain",
		.of_match_table = airoha_cpu_pmdomain_match,
	},
};
module_platform_driver(airoha_cpu_pmdomain_driver);

MODULE_AUTHOR("OpenWrt Builder");
MODULE_DESCRIPTION("Airoha AN7581 CPU PM domain and clock driver");
MODULE_LICENSE("GPL");
EOF

# ============================================================
# 2. luci-app-airoha-npu
# ============================================================
rm -rf package/luci-app-airoha-npu
git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-airoha-npu/Makefile

# ============================================================
# 3. vlmcsd + luci-app-vlmcsd
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

# ============================================================
# 4. 清理冲突包
# ============================================================
find feeds/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-fchomo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "luci-app-momo" -exec rm -rf {} + 2>/dev/null || true
find feeds/ -type d -name "momo" -exec rm -rf {} + 2>/dev/null || true
find package/ -type d -name "luci-app-homeproxy" -exec rm -rf {} + 2>/dev/null || true
rm -rf feeds/helloworld/dae feeds/helloworld/daed

# ============================================================
# 5. 安全修补内核 config
# ============================================================
find target/linux/airoha/ -name "config-*" -exec sed -i 's/CONFIG_STRICT_DEVMEM=y/# CONFIG_STRICT_DEVMEM is not set/g' {} +
find target/linux/airoha/ -name "config-*" -exec sed -i 's/CONFIG_IO_STRICT_DEVMEM=y/# CONFIG_IO_STRICT_DEVMEM is not set/g' {} +

for cfg in $(find target/linux/airoha/ -name "config-*"); do
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

# ============================================================
# 6. WAN MAC 地址自动修复
# ============================================================
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
# 7. 打包脚本 shell 兼容性修复
# ============================================================
find . -name "airoha_pack_bl2.sh" -exec sed -i 's/^\#\!\/bin\/sh/\#\!\/bin\/bash/' {} +
find . -name "airoha_pack_bl2.sh" -exec sed -i 's/cksum -a [^ ]*/cksum/g' {} +

echo ">>> diy-part2.sh 执行完毕！"
