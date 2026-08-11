#!/bin/bash
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)

set -e

echo "========================================="
echo ">>> 开始执行 diy-part2.sh 完整自定义脚本"
echo "========================================="

# ------------------------------------------------------------
# 1. 注入 CPU 频率驱动并清理冲突 Patch (针对 Linux 6.18 深度优化)
# ------------------------------------------------------------
echo ">>> [1/5] 正在配置 CPU 频率与 PM Domain 驱动..."
TARGET_C_DIR="target/linux/airoha/files/drivers/pmdomain/mediatek"
mkdir -p "$TARGET_C_DIR"

# 清理与自定义 C 文件冲突的 patch
rm -f target/linux/airoha/patches-6.18/221-02-pmdomain-airoha-Add-AN7583-cpufreq-compatible.patch

cat << 'EOF' > "$TARGET_C_DIR/airoha-cpu-pmdomain.c"
// SPDX-License-Identifier: GPL-2.0-only
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

#define AIROHA_CPU_PLL_BASE 0x1fa20000
#define AIROHA_CPU_PLL_PCW_OFFSET 0x2b4
#define AIROHA_CPU_PLL_CHG_OFFSET 0x2b8
#define AIROHA_CPU_PLL_PCW_INT_MASK GENMASK(30, 24)
#define AIROHA_CPU_PLL_POSDIV_MASK GENMASK(6, 4)

#define AIROHA_AVS_OP_GET_FREQ (AIROHA_AVS_OP_BASE | FIELD_PREP(AIROHA_AVS_OP_MASK, 0x2))

struct airoha_cpu_pmdomain_priv {
	struct clk_hw hw;
	struct generic_pm_domain pd;
	void __iomem *pll_pcw;
	void __iomem *pll_chg;
};

static unsigned long airoha_cpu_pmdomain_clk_get(struct clk_hw *hw, unsigned long parent_rate)
{
	struct airoha_cpu_pmdomain_priv *priv = container_of(hw, struct airoha_cpu_pmdomain_priv, hw);
	struct arm_smccc_res res;
	unsigned long freq;

	// 优先尝试通过 ARM SMC 调取 ATF 频率
	arm_smccc_1_1_invoke(AIROHA_SIP_AVS_HANDLE, AIROHA_AVS_OP_GET_FREQ, 0, 0, 0, 0, 0, 0, &res);
	freq = (unsigned long)(res.a0 * 1000 * 1000);

	// 如果 SMC 返回 0Hz，自动回退直接读取 CPU PLL 寄存器计算真实频率
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

static long airoha_cpu_pmdomain_clk_round_rate(struct clk_hw *hw, unsigned long rate, unsigned long *parent_rate)
{
	return airoha_cpu_pmdomain_clk_get(hw, *parent_rate);
}

static const struct clk_ops airoha_cpu_pmdomain_clk_ops = {
	.recalc_rate = airoha_cpu_pmdomain_clk_get,
	.round_rate = airoha_cpu_pmdomain_clk_round_rate,
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

	priv->pll_pcw = devm_ioremap(dev, AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_PCW_OFFSET, 0x4);
	priv->pll_chg = devm_ioremap(dev, AIROHA_CPU_PLL_BASE + AIROHA_CPU_PLL_CHG_OFFSET, 0x4);

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
	{ .compatible = "airoha,an7583-cpu-pmdomain" },
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

MODULE_LICENSE("GPL");
EOF

# 确保启用了 CPU PM Domain 驱动内核配置
if [ -f target/linux/airoha/config-6.18 ]; then
    grep -q "CONFIG_PMC_AIROHA_PMDOMAIN" target/linux/airoha/config-6.18 || \
    echo "CONFIG_PMC_AIROHA_PMDOMAIN=y" >> target/linux/airoha/config-6.18
fi

# ------------------------------------------------------------
# 2. 注入 WAN MAC 地址 +1 自动计算初始化脚本 (兼容 BusyBox Shell)
# ------------------------------------------------------------
echo ">>> [2/5] 正在配置 WAN MAC 地址 +1 规则..."
mkdir -p target/linux/airoha/base-files/etc/uci-defaults

cat << 'EOF' > target/linux/airoha/base-files/etc/uci-defaults/99-fix-wan-mac
#!/bin/sh

lan_mac=$(uci -q get network.lan.macaddr)
[ -z "$lan_mac" ] && lan_mac=$(cat /sys/class/net/eth0/address 2>/dev/null)

if [ -n "$lan_mac" ]; then
    mac_clean=$(echo "$lan_mac" | tr -d ':')
    # 使用标准 shell 算术展开，原生兼容所有 BusyBox 环境
    mac_dec=$((0x$mac_clean))
    
    if [ "$mac_dec" -gt 0 ] 2>/dev/null; then
        wan_dec=$((mac_dec + 1))
        # 格式化输出为标准的 MAC 格式
        wan_mac=$(printf "%012x" $wan_dec | sed 's/../&:/g;s/:$//')

        uci set network.wan.macaddr="$wan_mac"
        uci set network.wan6.macaddr="$wan_mac" 2>/dev/null || true
        uci commit network
    fi
fi

exit 0
EOF

chmod +x target/linux/airoha/base-files/etc/uci-defaults/99-fix-wan-mac

# ------------------------------------------------------------
# 3. 集成 Airoha NPU 控制插件 (luci-app-airoha-npu)
# ------------------------------------------------------------
echo ">>> [3/5] 正在添加 luci-app-airoha-npu 插件..."
rm -rf package/luci-app-airoha-npu
git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-airoha-npu/Makefile

# ------------------------------------------------------------
# 4. 集成 KMS 激活服务 (vlmcsd & luci-app-vlmcsd)
# ------------------------------------------------------------
echo ">>> [4/5] 正在添加 vlmcsd KMS 服务..."
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

# ------------------------------------------------------------
# 5. 清理第三方 Feed 构建冲突，并强制替换为可用的 tcping
# ------------------------------------------------------------
# ============================================================
# [DIY-P2] 彻底修复 tcping 缺失问题（动态生成标准 OpenWrt 包）
# ============================================================
echo ">>> [DIY-P2] 正在清理旧冲突并生成标准 tcping Package..."

# 1. 清理各种 feeds 里的旧冲突
rm -rf feeds/helloworld/dae feeds/helloworld/daed
rm -rf feeds/helloworld/tcping feeds/kenzo/tcping
rm -rf package/feeds/helloworld/tcping package/feeds/kenzo/tcping
rm -rf package/tcping

# 2. 手动创建标准的 OpenWrt 包目录结构并写入 Makefile
mkdir -p package/tcping
cat > package/tcping/Makefile << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=tcping
PKG_VERSION:=0.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/kenzok8/tcping/tar.gz/$(PKG_VERSION)?
PKG_HASH:=10a9af5062c2eac8a2d60776404565052c875b4582b378248163facc47dbb10f

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=license.txt

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/tcping
  SECTION:=net
  CATEGORY:=Network
  TITLE:=tcping measures the latency of a tcp-connection
  URL:=https://github.com/kenzok8/tcping
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -Wall" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/tcping/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tcping $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,tcping))
EOF

# 3. 移除 Passwall2 对 tcping 的硬性强制依赖 (做一层双保险)
sed -i 's/+tcping//g' feeds/helloworld/luci-app-passwall2/Makefile 2>/dev/null || true
sed -i 's/+tcping//g' package/feeds/helloworld/luci-app-passwall2/Makefile 2>/dev/null || true

# 4. 强制刷新索引缓存并选中包
rm -rf tmp/.packageinfo tmp/.packageauxvar tmp/.targetinfo
echo "CONFIG_PACKAGE_tcping=y" >> .config

echo ">>> [DIY-P2] tcping 标准包配置完成！"

echo "========================================="
echo ">>> diy-part2.sh 全部执行完毕！"
echo "========================================="
