# NVMeter

**[English](README.md)** | 简体中文

[![下载](https://img.shields.io/github/v/release/hualiu77/NVMeter?label=下载%20DMG&style=for-the-badge&color=2BB1B8&logo=apple)](https://github.com/hualiu77/NVMeter/releases/latest)
&nbsp;
[![CI](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Apple 公证](https://img.shields.io/badge/公证-Apple-success?logo=apple)](#安装)

macOS 原生菜单栏 SMART 监控,支持内置与外置 NVMe/SATA SSD。
个人使用永久免费、永久开源。

官网:**https://hualiu77.github.io/NVMeter/**

## 安装

1. 下载最新的 [**NVMeter-x.y.z.dmg**](https://github.com/hualiu77/NVMeter/releases/latest)(Developer ID 签名 + Apple 公证,无任何 Gatekeeper 警告)。
2. 打开 DMG,把 **NVMeter.app** 拖进 **Applications** 文件夹。
3. 用 Spotlight 启动(`⌘+空格 → NVMeter`),菜单栏会出现芯片图标。

要求 **macOS 14 Sonoma 或更高**,**Apple 芯片** Mac。从 v0.2.1 起内置 Sparkle 自动更新,以后无需手动下载。

## 为什么做这个

macOS 没有任何官方方式查看 SSD 的温度、磨损和剩余备用块。`smartctl` 能干活但只有命令行;Mac 上的图形界面方案要么闭源收费,要么早已停止维护。NVMeter 是架在 `smartctl` 之上的轻量原生 SwiftUI 菜单栏应用:

- 菜单栏常驻显示最热硬盘的温度(绿/黄/红);
- 读取内置 SSD **和** USB / 雷电外置硬盘盒的完整 SMART/NVMe 健康数据;
- 本地 SQLite 记录历史,24 小时 / 7 天 / 30 天趋势图;
- **磁盘测速**:CrystalDiskMark 风格条状图,测速时同步记录温度叠加成曲线——能解释 SLC 缓存耗尽 vs 过热降速,这是纯测速工具做不到的;还会标出接口理论上限作对比;
- 温度跨越阈值时发系统通知——**无云端、无遥测**;
- 点击设备卡片查看全部 SMART 属性(故障预警 / 寿命计数分组)。

## 项目价值观

1. **个人使用永久免费。** 核心监控功能采用 AGPL-3.0,永不移入付费墙。开源/商业边界见 [BUSINESS.md](BUSINESS.md)。
2. **设备兼容数据库归社区所有。** USB / 雷电桥接芯片的兼容参数放在独立的**公共领域(CC0)**仓库 [NVMeter-drivedb](https://github.com/hualiu77/NVMeter-drivedb)。贡献一个新硬盘盒只需一个 YAML 文件,不用写 Swift;App 内置"帮我们识别这个硬盘盒"按钮,一键生成诊断报告。
3. **开源版本永远没有遥测。**

## 已知局限(提前说清楚)

### ✅ 完整支持

- **内置 Apple SSD**(Apple Fabric NVMe)——温度、磨损、备用块、介质错误。
- **雷电 3 / 4 / 5 NVMe 硬盘盒与扩展坞**——按原生 PCIe 读取,无需任何参数,完整 NVMe 健康日志。
- **使用配合型桥接芯片的 USB-NVMe 硬盘盒**——按社区数据库自动重试 `-d` 参数。

### ⚠️ 常见受阻:USB-SATA 硬盘盒与外置机械盘

很多 USB-SATA 桥接芯片在 macOS 上拒绝透传 SMART 命令,无论用什么参数都返回 `Operation not supported by device`。这**不是** NVMeter 的 bug——是 macOS 用户态 SCSI 栈的根本限制。Linux 内核有通用 SAT 翻译层,macOS 没有;闭源软件靠内核扩展绕过,但 Apple 芯片上装 kext 需要关闭安全特性,NVMeter 不走这条路。

遇到这类设备时,NVMeter 在卡片上如实说明,容量与连接信息照常显示;若该桥接芯片已被社区收录,还会显示"已收录于数据库"。

### ⛔ 不支持

- 光驱、RAID 卷、硬件 RAID 后面的硬盘。
- 磁盘镜像(sparsebundle、模拟器卷等虚拟设备)。
- 存储卡(SD/CF)——本身没有 SMART,但容量信息正常显示。

## 从源码构建

要求:macOS 14+、Xcode 15+ / Swift 5.9+、`brew install smartmontools`。

```bash
git clone https://github.com/hualiu77/NVMeter.git
cd NVMeter
swift build
swift test
swift run NVMeterApp     # 开发模式,调用 /opt/homebrew/bin/smartctl
```

构建与 Releases 页相同的签名公证 `.app` + `.dmg`:

```bash
# 一次性配置(先在 appleid.apple.com 生成 App 专用密码):
xcrun notarytool store-credentials nvmeter-notarize \
    --apple-id "<你的 Apple ID>" --team-id <你的 Team ID>

# 之后每次发版一条命令:
VERSION=x.y.z NOTARIZE=1 MAKE_DMG=1 APPCAST=1 bash scripts/build-app.sh
```

完整流水线见 `scripts/build-app.sh`(嵌入 smartctl 与 Sparkle、逐层签名、公证、stapler、DMG、appcast)。

## 参与贡献

- **添加新硬盘盒支持?** 向 [NVMeter-drivedb](https://github.com/hualiu77/NVMeter-drivedb) 提交 YAML PR——不需要会 Swift,见其 `CONTRIBUTING.md`;或者直接用 App 里的一键上报按钮。
- **改代码?** 见 [CONTRIBUTING.md](CONTRIBUTING.md)。非琐碎 PR 需签署 [CLA](CLA.md),以便项目在保持自由的同时维持开源/商业双许可。

## 许可证

NVMeter 采用 **AGPL-3.0-or-later**,见 [LICENSE](LICENSE)。

NVMeter 内嵌并依赖 **smartmontools**(`smartctl`,GPL-2.0-or-later),完整致谢与源码获取方式见 [NOTICE](NOTICE)。

本程序按"现状"提供,**不含任何担保**。**NVMeter 不能替代备份。**
