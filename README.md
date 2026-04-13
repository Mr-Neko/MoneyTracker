# MoneyTracker 记账本

一款简洁美观的 iOS 记账 App，使用 SwiftUI 构建，支持**账单自动导入**。

## 核心功能

### 记账
- 手动记账：支出/收入、10 个分类、5 个支付渠道
- 统计分析：分类/渠道饼图、每日支出趋势柱状图
- 按日分组明细列表、月度概览卡片、日预算进度

### 账单自动化导入
- **邮箱自动拉取**：配置 IMAP 邮箱，自动搜索并下载微信/支付宝发送的账单 CSV
- **CSV 智能解析**：自动识别微信、支付宝、招商银行等格式，智能分类
- **文件选择器导入**：从「文件」App 手动选取 CSV 文件
- **短信文本解析**：粘贴银行扣款短信，正则提取金额/商家/日期
- **分享扩展导入**：从微信/邮件等 App 直接分享 CSV 到本 App
- **iOS 快捷指令**：Siri 语音记账、定时自动拉取、自动清理

### 本地账单归档 (BillArchive)
- 所有导入的 CSV 原文件自动归档到 `Documents/BillArchive/`
- 按来源分子目录：`wechat/` `alipay/` `bank/` `sms/`
- **自动保留 6 个月**，过期文件启动时自动清理
- 支持手动管理：查看、删除单个文件、清空全部

## 自动化架构

```
┌─────────────────────────────────────────────────────────┐
│                    数据入口                               │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ 邮箱 IMAP │  │ 文件选择 │  │ 分享扩展 │  │ 短信粘贴│ │
│  │ 自动拉取  │  │  手动导入 │  │ 直接传入 │  │ 正则解析│ │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └────┬────┘ │
│        │             │             │             │       │
│        └─────────────┼─────────────┼─────────────┘       │
│                      ▼                                    │
│              ┌───────────────┐                            │
│              │  CSVParser    │  自动检测来源               │
│              │  智能解析引擎  │  微信/支付宝/银行/通用       │
│              └───────┬───────┘                            │
│                      │                                    │
│           ┌──────────┼──────────┐                        │
│           ▼                     ▼                        │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ BillStorageManager│  │ TransactionVM   │              │
│  │ 归档到 temp 目录  │  │ 去重后添加到列表 │              │
│  │ 6 个月自动清理    │  │ 更新统计图表     │              │
│  └─────────────────┘  └──────────────────┘              │
│                                                          │
│  ┌──────────────────────────────────────────┐           │
│  │ iOS App Intents (快捷指令)                │           │
│  │ • Siri 语音记账  • 定时自动拉取邮箱       │           │
│  │ • 今日支出查询   • 自动清理过期账单       │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

## 项目结构

```
MoneyTracker/
├── MoneyTrackerApp.swift           # App 入口 + URL Scheme
├── Models/
│   ├── Transaction.swift           # 数据模型
│   ├── CSVParser.swift             # CSV 多格式解析引擎
│   ├── BillStorageManager.swift    # 本地 temp 归档管理
│   ├── EmailBillFetcher.swift      # 邮箱 IMAP 自动拉取
│   └── AppIntentsProvider.swift    # iOS 快捷指令 + URL Scheme
├── ViewModels/
│   └── TransactionViewModel.swift  # 业务逻辑 + 批量导入去重
├── Views/
│   ├── MainTabView.swift           # 自定义 TabBar
│   ├── HomeView.swift              # 首页概览
│   ├── TransactionListView.swift   # 交易明细
│   ├── TransactionRowView.swift    # 交易行组件
│   ├── StatisticsView.swift        # 统计分析
│   ├── AddTransactionView.swift    # 手动记账
│   └── ImportView.swift            # 自动化导入中心
│       ├── EmailConfigView         # 邮箱配置
│       ├── SMSInputView            # 短信粘贴解析
│       ├── ArchiveManagerView      # 归档文件管理
│       └── ImportResultView        # 导入结果展示
└── Utils/
    └── Extensions.swift
```

## CSV 解析支持

| 格式 | 自动识别 | 字段映射 |
|------|----------|----------|
| 微信支付账单 | ✅ 头部特征检测 | 交易时间/对方/商品/收支/金额/支付方式 |
| 支付宝交易流水 | ✅ 头部特征检测 | 交易时间/对方/商品/金额/收支/状态 |
| 招商银行对账单 | ✅ 关键词检测 | 日期/摘要/金额/余额/对方 |
| 通用 CSV | ✅ 智能列匹配 | 自动识别日期/金额/备注/商家/收支列 |
| 银行短信 | ✅ 正则匹配 | 金额/商家/日期/收支方向 |

## 运行

1. Xcode 15+ 打开 `MoneyTracker.xcodeproj`
2. 选择 iPhone 模拟器 (iOS 16+)
3. ⌘R 运行

## 后续计划

- [ ] 集成 MailCore2 实现真实 IMAP 连接
- [ ] CoreData / SwiftData 数据持久化
- [ ] Share Extension Target 实现系统级分享导入
- [ ] Widget 小组件
- [ ] iCloud 同步
- [ ] 预算管理
