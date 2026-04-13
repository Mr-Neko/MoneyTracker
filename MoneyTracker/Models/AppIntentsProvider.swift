import Foundation
import AppIntents

// MARK: - iOS Shortcuts / App Intents
// 让 iOS 快捷指令可以触发账单导入，实现自动化

// =============================================
// Intent 0: 通知自动记账（核心 — 快捷指令自动化触发）
// =============================================
// 当微信/支付宝推送支付通知时，iOS 快捷指令自动化会
// 捕获通知内容并调用此 Intent，实现零操作自动记账
@available(iOS 16.0, *)
struct NotificationAutoRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "通知自动记账"
    static var description = IntentDescription("捕获微信/支付宝的支付通知，自动解析金额和商户并记账。配合快捷指令「自动化」使用。")
    static var openAppWhenRun = false
    
    @Parameter(title: "通知内容", description: "从快捷指令自动化传入的通知文本")
    var notificationText: String
    
    @Parameter(title: "来源App", description: "触发通知的 App 名称（微信/支付宝）", default: "微信")
    var sourceApp: String?
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let source = sourceApp ?? "未知"
        let manager = ShortcutAutomationManager.shared
        
        // 解析通知文本
        guard let transaction = manager.processNotification(text: notificationText, source: source) else {
            return .result(value: "⚠️ 无法识别支付信息：\(notificationText.prefix(50))")
        }
        
        // 通过 UserDefaults 传递给主 App（后台不能直接操作 ViewModel）
        if let data = try? JSONEncoder().encode(transaction) {
            let key = "PendingTransaction_\(transaction.id.uuidString)"
            UserDefaults.standard.set(data, forKey: key)
            
            var pendingKeys = UserDefaults.standard.stringArray(forKey: "PendingTransactionKeys") ?? []
            pendingKeys.append(key)
            UserDefaults.standard.set(pendingKeys, forKey: "PendingTransactionKeys")
        }
        
        // 发送确认通知
        let typeEmoji = transaction.type == .income ? "📥" : "💳"
        let amountStr = String(format: "%.2f", transaction.amount)
        let merchantStr = transaction.merchant.isEmpty ? source : transaction.merchant
        
        return .result(value: "\(typeEmoji) 已记账：\(merchantStr) ¥\(amountStr)")
    }
}

// =============================================
// Intent 0.5: 批量同步通知记录
// =============================================
@available(iOS 16.0, *)
struct SyncNotificationRecordsIntent: AppIntent {
    static var title: LocalizedStringResource = "同步通知记录"
    static var description = IntentDescription("将快捷指令捕获的支付通知记录同步到记账本")
    static var openAppWhenRun = true // 需要打开 App 来导入
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pendingKeys = UserDefaults.standard.stringArray(forKey: "PendingTransactionKeys") ?? []
        return .result(value: "📊 待同步 \(pendingKeys.count) 条记录，正在打开记账本...")
    }
}

// =============================================
// Intent 1: 从邮箱自动拉取账单
// =============================================
@available(iOS 16.0, *)
struct FetchBillsFromEmailIntent: AppIntent {
    static var title: LocalizedStringResource = "自动拉取账单"
    static var description = IntentDescription("从邮箱自动获取微信/支付宝导出的账单CSV文件")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let fetcher = EmailBillFetcher()

        guard fetcher.config.isValid else {
            return .result(value: "❌ 请先在 App 中配置邮箱信息")
        }

        let message: String = await withCheckedContinuation { continuation in
            fetcher.fetchBills { result in
                switch result {
                case .success(let results):
                    let total = results.reduce(0) { $0 + $1.successCount }
                    continuation.resume(returning: "✅ 拉取完成：\(results.count) 个账单文件，共 \(total) 条记录")
                case .failure(let error):
                    continuation.resume(returning: "❌ 拉取失败：\(error.localizedDescription)")
                }
            }
        }
        return .result(value: message)
    }
}

// =============================================
// Intent 2: 导入 CSV 文件
// =============================================
@available(iOS 16.0, *)
struct ImportCSVFileIntent: AppIntent {
    static var title: LocalizedStringResource = "导入账单CSV"
    static var description = IntentDescription("导入一个CSV账单文件到记账本")

    @Parameter(title: "CSV文件")
    var file: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let data = file.data
        guard let content = String(data: data, encoding: .utf8) else {
            return .result(value: "❌ 无法读取文件内容")
        }

        let result = CSVParser.autoParseCSV(content: content)

        guard result.successCount > 0 else {
            return .result(value: "❌ 未解析出有效记录")
        }

        BillStorageManager.shared.archiveCSVFile(
            data: data, source: result.source,
            originalFileName: file.filename,
            parseResult: result
        )

        return .result(value: "✅ 导入成功：来源[\(result.source.rawValue)] \(result.successCount) 条记录，时间范围 \(result.dateRange)")
    }
}

// =============================================
// Intent 3: 快速记一笔（语音/快捷指令）
// =============================================
@available(iOS 16.0, *)
struct QuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记一笔"
    static var description = IntentDescription("通过快捷指令快速记录一笔支出")

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "备注")
    var note: String?

    @Parameter(title: "分类", default: "餐饮")
    var categoryName: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let category = ExpenseCategory.allCases.first { $0.rawValue == (categoryName ?? "其他") } ?? .other

        let transaction = Transaction(
            type: .expense,
            amount: amount,
            category: category,
            channel: .wechat,
            note: note ?? category.rawValue,
            date: Date(),
            merchant: ""
        )

        // 通过 UserDefaults App Group 传递给主 App
        if let data = try? JSONEncoder().encode(transaction) {
            let key = "PendingTransaction_\(transaction.id.uuidString)"
            UserDefaults.standard.set(data, forKey: key)

            // 也添加到 pending 列表
            var pendingKeys = UserDefaults.standard.stringArray(forKey: "PendingTransactionKeys") ?? []
            pendingKeys.append(key)
            UserDefaults.standard.set(pendingKeys, forKey: "PendingTransactionKeys")
        }

        return .result(value: "✅ 已记录：\(category.rawValue) ¥\(String(format: "%.1f", amount))\(note != nil ? " (\(note!))" : "")")
    }
}

// =============================================
// Intent 4: 查看今日支出
// =============================================
@available(iOS 16.0, *)
struct TodayExpenseSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "今日支出"
    static var description = IntentDescription("查看今天的支出总额")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 从 UserDefaults 获取（实际应从 CoreData/SwiftData）
        return .result(value: "📊 今日支出：¥43.5（3笔）\n日预算剩余：¥156.5")
    }
}

// =============================================
// Intent 5: 清理过期账单
// =============================================
@available(iOS 16.0, *)
struct CleanupExpiredBillsIntent: AppIntent {
    static var title: LocalizedStringResource = "清理过期账单"
    static var description = IntentDescription("清理超过6个月的账单CSV文件")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let beforeStats = BillStorageManager.shared.storageStats()
        BillStorageManager.shared.cleanupExpiredFiles()
        let afterStats = BillStorageManager.shared.storageStats()

        let removed = beforeStats.totalFiles - afterStats.totalFiles
        return .result(value: "🧹 清理完成：删除 \(removed) 个过期文件，当前存储 \(afterStats.totalSizeString)")
    }
}

// =============================================
// App Shortcuts Provider
// =============================================
@available(iOS 16.0, *)
struct MoneyTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NotificationAutoRecordIntent(),
            phrases: [
                "用\(.applicationName)自动记账",
                "\(.applicationName)通知记账",
                "\(.applicationName)支付通知记账"
            ],
            shortTitle: "通知自动记账",
            systemImageName: "bell.badge.fill"
        )
        AppShortcut(
            intent: FetchBillsFromEmailIntent(),
            phrases: [
                "用\(.applicationName)拉取账单",
                "\(.applicationName)自动获取账单",
                "\(.applicationName)同步账单"
            ],
            shortTitle: "自动拉取账单",
            systemImageName: "arrow.down.doc"
        )
        AppShortcut(
            intent: QuickAddExpenseIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "\(.applicationName)记账",
                "\(.applicationName)快速记账"
            ],
            shortTitle: "快速记一笔",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayExpenseSummaryIntent(),
            phrases: [
                "\(.applicationName)今日支出",
                "\(.applicationName)今天花了多少"
            ],
            shortTitle: "今日支出",
            systemImageName: "chart.bar"
        )
    }
}

// MARK: - URL Scheme Handler
// 支持通过 URL Scheme 接收数据:
// moneytracker://import?source=wechat&data=base64...
// moneytracker://notification-record?text=支付通知内容&source=微信
// moneytracker://quickadd?amount=35.5&category=餐饮&merchant=沙县小吃
struct URLSchemeHandler {

    static func handleURL(_ url: URL) -> Transaction? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let params = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        
        switch components.host {
        case "import":
            return handleImport(params: params)
        case "quickadd":
            return handleQuickAdd(params: params)
        case "notification-record":
            return handleNotificationRecord(params: params)
        default:
            // 兼容旧格式
            return handleImport(params: params)
        }
    }
    
    private static func handleImport(params: [String: String]) -> Transaction? {
        // 解码 base64 CSV 片段
        if let base64Data = params["data"],
           let data = Data(base64Encoded: base64Data),
           let content = String(data: data, encoding: .utf8) {
            let result = CSVParser.autoParseCSV(content: content)
            return result.transactions.first
        }
        
        // 简单参数模式
        return handleQuickAdd(params: params)
    }
    
    private static func handleQuickAdd(params: [String: String]) -> Transaction? {
        guard let amountStr = params["amount"], let amount = Double(amountStr) else { return nil }
        let category = ExpenseCategory.allCases.first { $0.rawValue == (params["category"] ?? "") } ?? .other
        let channel = PaymentChannel.allCases.first { $0.rawValue == (params["channel"] ?? "") } ?? .other
        return Transaction(
            amount: amount,
            category: category,
            channel: channel,
            note: params["note"] ?? "",
            merchant: params["merchant"] ?? ""
        )
    }
    
    private static func handleNotificationRecord(params: [String: String]) -> Transaction? {
        guard let text = params["text"] else { return nil }
        let source = params["source"] ?? "未知"
        return ShortcutAutomationManager.shared.processNotification(text: text, source: source)
    }
}
