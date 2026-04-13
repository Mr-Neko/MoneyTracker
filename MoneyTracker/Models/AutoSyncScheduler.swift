import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - 后台自动同步调度器
// 利用 BGAppRefreshTask 在后台定期拉取新交易
// 结合 Local Notification 在检测到新交易时通知用户
class AutoSyncScheduler: ObservableObject {

    static let shared = AutoSyncScheduler()
    static let backgroundTaskId = "com.demo.MoneyTracker.sync"
    static let processingTaskId = "com.demo.MoneyTracker.cleanup"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "AutoSync.enabled") }
    }
    @Published var syncInterval: SyncInterval {
        didSet { UserDefaults.standard.set(syncInterval.rawValue, forKey: "AutoSync.interval") }
    }
    @Published var notifyOnNewTransaction: Bool {
        didSet { UserDefaults.standard.set(notifyOnNewTransaction, forKey: "AutoSync.notify") }
    }
    @Published var lastBackgroundSync: Date?
    @Published var backgroundSyncCount: Int = 0

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "AutoSync.enabled")
        let rawInterval = UserDefaults.standard.string(forKey: "AutoSync.interval") ?? SyncInterval.hourly.rawValue
        syncInterval = SyncInterval(rawValue: rawInterval) ?? .hourly
        notifyOnNewTransaction = UserDefaults.standard.object(forKey: "AutoSync.notify") as? Bool ?? true
        lastBackgroundSync = UserDefaults.standard.object(forKey: "AutoSync.lastBg") as? Date
        backgroundSyncCount = UserDefaults.standard.integer(forKey: "AutoSync.bgCount")
    }

    // MARK: - 注册后台任务（在 App 启动时调用）
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskId, using: nil) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingTaskId, using: nil) { task in
            self.handleBackgroundCleanup(task: task as! BGProcessingTask)
        }
    }

    // MARK: - 调度下次后台同步
    func scheduleNextSync() {
        guard isEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: syncInterval.seconds)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ 后台任务调度失败: \(error)")
        }
    }

    // MARK: - 调度后台清理（每周一次）
    func scheduleCleanup() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7 * 24 * 3600)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - 处理后台同步
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        // 调度下一次
        scheduleNextSync()

        let syncTask = Task {
            if #available(iOS 17.4, *) {
                let monitor = FinanceKitMonitor()
                await monitor.requestAuthorization()
                let newTxs = await monitor.syncNewTransactions()

                if !newTxs.isEmpty && notifyOnNewTransaction {
                    await sendNewTransactionNotification(transactions: newTxs)
                }

                // 保存待处理的交易到 UserDefaults，下次打开 App 时导入
                savePendingTransactions(newTxs)

                await MainActor.run {
                    lastBackgroundSync = Date()
                    backgroundSyncCount += newTxs.count
                    UserDefaults.standard.set(Date(), forKey: "AutoSync.lastBg")
                    UserDefaults.standard.set(backgroundSyncCount, forKey: "AutoSync.bgCount")
                }
            }

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - 处理后台清理
    private func handleBackgroundCleanup(task: BGProcessingTask) {
        scheduleCleanup()

        BillStorageManager.shared.cleanupExpiredFiles()
        task.setTaskCompleted(success: true)
    }

    // MARK: - 本地通知
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                print("⚠️ 通知权限被拒绝")
            }
        }
    }

    private func sendNewTransactionNotification(transactions: [Transaction]) async {
        let count = transactions.count
        let totalAmount = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

        let content = UNMutableNotificationContent()
        content.title = "💳 新消费记录"

        if count == 1, let tx = transactions.first {
            content.body = "\(tx.merchant) ¥\(String(format: "%.2f", tx.amount)) 已自动记账"
            content.subtitle = tx.category.rawValue
        } else {
            content.body = "检测到 \(count) 笔新交易，共 ¥\(String(format: "%.0f", totalAmount))，已自动入账"
        }

        content.sound = .default
        content.badge = NSNumber(value: count)

        let request = UNNotificationRequest(
            identifier: "auto-sync-\(UUID().uuidString)",
            content: content,
            trigger: nil // 立即发送
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 待处理交易暂存
    private func savePendingTransactions(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }

        var pending = loadPendingTransactions()
        pending.append(contentsOf: transactions)

        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: "AutoSync.pendingTxs")
        }
    }

    func loadPendingTransactions() -> [Transaction] {
        guard let data = UserDefaults.standard.data(forKey: "AutoSync.pendingTxs") else { return [] }
        return (try? JSONDecoder().decode([Transaction].self, from: data)) ?? []
    }

    func clearPendingTransactions() {
        UserDefaults.standard.removeObject(forKey: "AutoSync.pendingTxs")
    }
}

// MARK: - 同步频率
enum SyncInterval: String, CaseIterable, Identifiable {
    case fifteenMin = "15分钟"
    case halfHour = "30分钟"
    case hourly = "1小时"
    case threeHours = "3小时"
    case daily = "每天"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMin: return 15 * 60
        case .halfHour: return 30 * 60
        case .hourly: return 3600
        case .threeHours: return 3 * 3600
        case .daily: return 24 * 3600
        }
    }
}
