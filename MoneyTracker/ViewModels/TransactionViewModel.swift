import Foundation
import SwiftUI

class TransactionViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var selectedMonth: Date = Date()
    @Published var financeKitEnabled = false

    private var financeKitMonitor: AnyObject? // FinanceKitMonitor (iOS 17+)

    init() {
        loadSampleData()
    }

    // MARK: - FinanceKit 自动监控
    @available(iOS 17.4, *)
    func setupFinanceKit() async {
        let monitor = FinanceKitMonitor()

        guard FinanceKitMonitor.isAvailable else {
            return
        }

        await monitor.requestAuthorization()
        guard monitor.isAuthorized else { return }

        // 拉取历史交易
        let historicalTxs = await monitor.syncNewTransactions()
        await MainActor.run {
            let added = importTransactions(historicalTxs)
            financeKitEnabled = true
            financeKitMonitor = monitor
            print("📊 FinanceKit 历史同步: \(added) 条新记录")
        }

        // 启动实时监听 — 每笔新消费自动入账
        monitor.startRealTimeMonitoring { [weak self] newTx in
            guard let self = self else { return }
            let _ = self.importTransactions([newTx])
        }
    }

    // MARK: - 模拟数据
    func loadSampleData() {
        let calendar = Calendar.current
        let now = Date()

        let sampleData: [(Double, ExpenseCategory, PaymentChannel, String, String, Int, TransactionType)] = [
            // 今天
            (35.5, .food, .wechat, "午餐-沙县小吃", "沙县小吃", 0, .expense),
            (8.0, .transport, .alipay, "地铁通勤", "北京地铁", 0, .expense),
            (15800, .other, .bankCard, "工资到账", "公司", 0, .income),
            // 昨天
            (128.0, .shopping, .alipay, "日用品采购", "盒马鲜生", -1, .expense),
            (25.0, .food, .wechat, "早餐+咖啡", "瑞幸咖啡", -1, .expense),
            (6.5, .transport, .wechat, "公交", "北京公交", -1, .expense),
            // 前天
            (299.0, .shopping, .alipay, "买了件衣服", "优衣库", -2, .expense),
            (42.0, .food, .wechat, "晚餐外卖", "美团外卖", -2, .expense),
            (200.0, .transfer, .wechat, "朋友还钱", "张三", -2, .income),
            // 3天前
            (1500.0, .housing, .bankCard, "房租水电", "房东", -3, .expense),
            (68.0, .food, .alipay, "聚餐AA", "海底捞", -3, .expense),
            // 4天前
            (89.0, .entertainment, .wechat, "电影票", "万达影城", -4, .expense),
            (35.0, .food, .wechat, "午餐", "麦当劳", -4, .expense),
            // 5天前
            (200.0, .medical, .alipay, "挂号+药费", "朝阳医院", -5, .expense),
            (15.0, .transport, .alipay, "打车", "滴滴出行", -5, .expense),
            // 6天前
            (49.9, .education, .wechat, "买了本书", "微信读书", -6, .expense),
            (120.0, .utilities, .bankCard, "电费", "国家电网", -6, .expense),
            (500.0, .other, .wechat, "红包收入", "李四", -6, .income),
            // 一周前
            (2000.0, .shopping, .alipay, "数码配件", "京东", -7, .expense),
            (55.0, .food, .wechat, "下午茶", "星巴克", -7, .expense),
            // 更早
            (85.0, .food, .alipay, "周末聚餐", "西贝莜面村", -10, .expense),
            (30.0, .transport, .alipay, "打车回家", "滴滴出行", -10, .expense),
            (666.0, .transfer, .bankCard, "转账收入", "家人", -12, .income),
            (3200.0, .housing, .bankCard, "房租", "房东", -15, .expense),
            (168.0, .entertainment, .alipay, "KTV", "好乐迪", -18, .expense),
            (45.0, .food, .wechat, "外卖", "饿了么", -20, .expense),
        ]

        transactions = sampleData.map { data in
            let date = calendar.date(byAdding: .day, value: data.5, to: now)!
            return Transaction(
                type: data.6,
                amount: data.0,
                category: data.1,
                channel: data.2,
                note: data.3,
                date: date,
                merchant: data.4
            )
        }.sorted { $0.date > $1.date }
    }

    // MARK: - 添加交易
    func addTransaction(_ transaction: Transaction) {
        transactions.insert(transaction, at: 0)
        transactions.sort { $0.date > $1.date }
        autoSyncToICloud()
    }

    // MARK: - 删除交易
    func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        autoSyncToICloud()
    }

    // MARK: - 批量导入（去重）
    @discardableResult
    func importTransactions(_ newTransactions: [Transaction]) -> Int {
        var added = 0
        for tx in newTransactions {
            // 去重：相同日期+金额+商家 视为重复
            let isDuplicate = transactions.contains { existing in
                abs(existing.date.timeIntervalSince(tx.date)) < 60 &&
                existing.amount == tx.amount &&
                existing.merchant == tx.merchant &&
                existing.channel == tx.channel
            }
            if !isDuplicate {
                transactions.append(tx)
                added += 1
            }
        }
        transactions.sort { $0.date > $1.date }
        if added > 0 { autoSyncToICloud() }
        return added
    }

    // MARK: - 替换全部交易（iCloud 下载覆盖用）
    func replaceAllTransactions(_ newTransactions: [Transaction]) {
        transactions = newTransactions.sorted { $0.date > $1.date }
    }

    // MARK: - iCloud 自动同步
    private func autoSyncToICloud() {
        guard ICloudSyncManager.shared.autoSyncEnabled,
              ICloudSyncManager.shared.iCloudAvailable else { return }
        ICloudSyncManager.shared.uploadToCloud(transactions: transactions)
    }

    // MARK: - 导入快捷指令待处理记录
    func importPendingShortcutRecords() {
        let keys = UserDefaults.standard.stringArray(forKey: "PendingTransactionKeys") ?? []
        for key in keys {
            if let data = UserDefaults.standard.data(forKey: key),
               let tx = try? JSONDecoder().decode(Transaction.self, from: data) {
                addTransaction(tx)
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: "PendingTransactionKeys")
    }

    // MARK: - App 启动时自动清理过期账单
    func performStartupTasks() {
        BillStorageManager.shared.cleanupExpiredFiles()
        importPendingShortcutRecords()

        // 导入后台同步期间暂存的交易
        let pendingTxs = AutoSyncScheduler.shared.loadPendingTransactions()
        if !pendingTxs.isEmpty {
            let added = importTransactions(pendingTxs)
            AutoSyncScheduler.shared.clearPendingTransactions()
            print("📥 后台同步待入账: \(added) 条")
        }

        // 自动启动 FinanceKit 监控
        if #available(iOS 17.4, *) {
            Task { await setupFinanceKit() }
        }

        // 调度后台任务
        AutoSyncScheduler.shared.scheduleNextSync()
        AutoSyncScheduler.shared.scheduleCleanup()
        
        // 检查快捷指令安装状态（从快捷指令 App 返回时）
        ShortcutAutomationManager.shared.checkInstallationStatus()
    }

    // MARK: - 本月统计
    var monthlyStats: MonthlyStatistics {
        let calendar = Calendar.current
        let monthTransactions = transactions.filter {
            calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }

        let expenses = monthTransactions.filter { $0.type == .expense }
        let incomes = monthTransactions.filter { $0.type == .income }

        let totalExpense = expenses.reduce(0) { $0 + $1.amount }
        let totalIncome = incomes.reduce(0) { $0 + $1.amount }

        // 分类统计
        var categoryMap: [ExpenseCategory: Double] = [:]
        for t in expenses {
            categoryMap[t.category, default: 0] += t.amount
        }
        let categoryBreakdown = categoryMap.map { (category: $0.key, amount: $0.value, percentage: totalExpense > 0 ? $0.value / totalExpense * 100 : 0) }
            .sorted { $0.amount > $1.amount }

        // 渠道统计
        var channelMap: [PaymentChannel: Double] = [:]
        for t in expenses {
            channelMap[t.channel, default: 0] += t.amount
        }
        let channelBreakdown = channelMap.map { (channel: $0.key, amount: $0.value, percentage: totalExpense > 0 ? $0.value / totalExpense * 100 : 0) }
            .sorted { $0.amount > $1.amount }

        // 每日支出
        var dailyMap: [Date: Double] = [:]
        for t in expenses {
            let day = calendar.startOfDay(for: t.date)
            dailyMap[day, default: 0] += t.amount
        }
        let dailyExpenses = dailyMap.map { (date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }

        return MonthlyStatistics(
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            categoryBreakdown: categoryBreakdown,
            channelBreakdown: channelBreakdown,
            dailyExpenses: dailyExpenses
        )
    }

    // MARK: - 按日分组
    var groupedByDate: [(date: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        let monthTransactions = transactions.filter {
            calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }

        let grouped = Dictionary(grouping: monthTransactions) {
            calendar.startOfDay(for: $0.date)
        }

        return grouped.map { (date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 今日支出
    var todayExpense: Double {
        let calendar = Calendar.current
        return transactions
            .filter { calendar.isDateInToday($0.date) && $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
}
