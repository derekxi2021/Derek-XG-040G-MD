#!/bin/bash
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)

set -e

echo "========================================="
echo ">>> 开始执行 diy-part2.sh 完整自定义脚本"
echo "========================================="

# ------------------------------------------------------------
# 1. 配置 CPU 频率驱动 (采用源码原生 Patch + 开启内核 Config)
# ------------------------------------------------------------
echo ">>> [1/5] 正在配置 CPU 频率与 PM Domain 驱动..."

# 1. 彻底清理之前手动注入的 C 文件和 Makefile，避免冲突导致 Patch 失败
rm -rf target/linux/airoha/files/drivers/pmdomain/mediatek/airoha-cpu-pmdomain.c
rm -rf target/linux/airoha/files/drivers/pmdomain/mediatek/Makefile

# 2. 同步开启 target 层级的内核配置宏，让原生 221-02 Patch 的驱动生效
find target/linux/airoha/ -name "config-*" | while read -r config_file; do
    grep -q "CONFIG_AIROHA_CPU_PM_DOMAIN" "$config_file" || echo "CONFIG_AIROHA_CPU_PM_DOMAIN=y" >> "$config_file"
done

# ------------------------------------------------------------
# 2. 注入 WAN MAC 地址 +1 规则 (通用打包路径 + 稳健的尾字节计算)
# ------------------------------------------------------------
echo ">>> [2/5] 正在配置 WAN MAC 地址 +1 规则..."

mkdir -p files/etc/uci-defaults
mkdir -p target/linux/generic/base-files/etc/uci-defaults

cat << 'EOF' > files/etc/uci-defaults/99-fix-wan-mac
#!/bin/sh

lan_mac=$(uci -q get network.lan.macaddr)
[ -z "$lan_mac" ] && lan_mac=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/dsa-mgr/address 2>/dev/null)

if [ -n "$lan_mac" ]; then
    # 提取前 5 组和最后 1 组十六进制数，避免大整数做数学运算溢出
    prefix=$(echo "$lan_mac" | awk -F: '{print $1":"$2":"$3":"$4":"$5}')
    last_hex=$(echo "$lan_mac" | awk -F: '{print $6}')
    
    if [ -n "$last_hex" ]; then
        last_dec=$(printf "%d" "0x$last_hex")
        next_dec=$(( (last_dec + 1) % 256 ))
        next_hex=$(printf "%02x" $next_dec)
        
        wan_mac="${prefix}:${next_hex}"

        uci set network.wan.macaddr="$wan_mac"
        uci set network.wan6.macaddr="$wan_mac" 2>/dev/null || true
        uci commit network
    fi
fi

exit 0
EOF

# 双保险多路径复制并赋予执行权限
cp files/etc/uci-defaults/99-fix-wan-mac target/linux/generic/base-files/etc/uci-defaults/99-fix-wan-mac 2>/dev/null || true

chmod +x files/etc/uci-defaults/99-fix-wan-mac
chmod +x target/linux/generic/base-files/etc/uci-defaults/99-fix-wan-mac 2>/dev/null || true

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
# 5. 清理第三方 Feed 构建冲突，彻底修复 tcping 缺失问题（动态生成标准 OpenWrt 包）
# ------------------------------------------------------------
# ============================================================
# [DIY-P2] 1. 彻底清理引发 Kconfig 循环依赖和 Warning 的病态包
# ============================================================
echo ">>> [DIY-P2] 正在清理问题插件以修复 Kconfig 递归错误..."

# 清理导致 recursive dependency error 的根源插件
rm -rf feeds/helloworld/luci-app-fchomo package/feeds/helloworld/luci-app-fchomo 2>/dev/null || true
rm -rf feeds/helloworld/luci-app-homeproxy package/feeds/helloworld/luci-app-homeproxy 2>/dev/null || true
rm -rf feeds/helloworld/luci-app-momo feeds/helloworld/momo package/feeds/helloworld/luci-app-momo package/feeds/helloworld/momo 2>/dev/null || true

# 清理导致 Warning 的缺失依赖插件
rm -rf feeds/helloworld/luci-app-daede package/feeds/helloworld/luci-app-daede 2>/dev/null || true
rm -rf feeds/helloworld/dae feeds/helloworld/daed 2>/dev/null || true
rm -rf feeds/helloworld/tcping feeds/kenzo/tcping package/feeds/helloworld/tcping package/feeds/kenzo/tcping 2>/dev/null || true

# ============================================================
# [DIY-P2] 2. 导入 Passwall 官方标准的 tcping 包
# ============================================================
echo ">>> [DIY-P2] 正在导入 Passwall 官方 tcping Package..."
rm -rf package/tcping /tmp/pw-pkgs

# 拉取 Passwall 官方 packages 仓库并提取 tcping
git clone --depth=1 https://github.com/openwrt-passwall/openwrt-passwall-packages.git /tmp/pw-pkgs
cp -a /tmp/pw-pkgs/tcping package/tcping
rm -rf /tmp/pw-pkgs

# 解除 Passwall / Passwall2 Makefile 对 tcping 的硬绑定
sed -i 's/+tcping//g' feeds/helloworld/luci-app-passwall2/Makefile 2>/dev/null || true
sed -i 's/+tcping//g' package/feeds/helloworld/luci-app-passwall2/Makefile 2>/dev/null || true
sed -i 's/+tcping//g' feeds/helloworld/luci-app-passwall/Makefile 2>/dev/null || true

# ============================================================
# [DIY-P2] 3. 刷新 OpenWrt 数据库索引并注入配置
# ============================================================
echo ">>> [DIY-P2] 刷新 package 缓存树..."
rm -rf tmp/.packageinfo tmp/.packageauxvar tmp/.targetinfo

# 强制注入 tcping 选中状态
echo "CONFIG_PACKAGE_tcping=y" >> .config

echo ">>> [DIY-P2] 修复完成！Kconfig 递归依赖与 tcping 问题均已清理。"

echo "========================================="
echo ">>> diy-part2.sh 全部执行完毕！"
echo "========================================="
