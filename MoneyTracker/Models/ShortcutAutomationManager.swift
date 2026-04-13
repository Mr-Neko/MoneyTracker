import Foundation
import SwiftUI

// MARK: - 快捷指令自动化管理器
// 管理 iOS 快捷指令的配置、安装引导、运行状态
// 核心功能：一键生成预制快捷指令、监控自动化状态、记录捕获日志

class ShortcutAutomationManager: ObservableObject {
    
    static let shared = ShortcutAutomationManager()
    
    // MARK: - 状态属性
    @Published var isWechatAutomationEnabled: Bool {
        didSet { UserDefaults.standard.set(isWechatAutomationEnabled, forKey: "Shortcut.wechat.enabled") }
    }
    @Published var isAlipayAutomationEnabled: Bool {
        didSet { UserDefaults.standard.set(isAlipayAutomationEnabled, forKey: "Shortcut.alipay.enabled") }
    }
    @Published var captureCount: Int {
        didSet { UserDefaults.standard.set(captureCount, forKey: "Shortcut.captureCount") }
    }
    @Published var lastCaptureDate: Date? {
        didSet { UserDefaults.standard.set(lastCaptureDate, forKey: "Shortcut.lastCapture") }
    }
    @Published var recentRecords: [NotificationRecord] = []
    @Published var todayCaptureCount: Int = 0
    @Published var todayCaptureAmount: Double = 0
    
    // 快捷指令安装状态
    @Published var wechatShortcutInstalled: Bool {
        didSet { UserDefaults.standard.set(wechatShortcutInstalled, forKey: "Shortcut.wechat.installed") }
    }
    @Published var alipayShortcutInstalled: Bool {
        didSet { UserDefaults.standard.set(alipayShortcutInstalled, forKey: "Shortcut.alipay.installed") }
    }
    
    private let maxRecords = 100
    
    private init() {
        isWechatAutomationEnabled = UserDefaults.standard.bool(forKey: "Shortcut.wechat.enabled")
        isAlipayAutomationEnabled = UserDefaults.standard.bool(forKey: "Shortcut.alipay.enabled")
        captureCount = UserDefaults.standard.integer(forKey: "Shortcut.captureCount")
        lastCaptureDate = UserDefaults.standard.object(forKey: "Shortcut.lastCapture") as? Date
        wechatShortcutInstalled = UserDefaults.standard.bool(forKey: "Shortcut.wechat.installed")
        alipayShortcutInstalled = UserDefaults.standard.bool(forKey: "Shortcut.alipay.installed")
        loadRecords()
        updateTodayStats()
    }
    
    // MARK: - 处理来自快捷指令的通知文本
    // 这是快捷指令调用 App Intent 时的核心入口
    func processNotification(text: String, source: String) -> Transaction? {
        let result = NotificationParser.parse(notificationText: text, source: source)
        
        // 记录日志
        let record = NotificationRecord(source: source, rawText: text, result: result)
        addRecord(record)
        
        guard let result = result, result.isValid else {
            return nil
        }
        
        let transaction = Transaction(
            type: result.type,
            amount: result.amount,
            category: result.category,
            channel: result.channel,
            note: result.merchant.isEmpty ? "\(source)支付" : result.merchant,
            date: Date(),
            merchant: result.merchant
        )
        
        // 更新统计
        captureCount += 1
        lastCaptureDate = Date()
        updateTodayStats()
        
        return transaction
    }
    
    // MARK: - 快捷指令安装引导
    // 生成 iOS 快捷指令的安装 URL
    // iOS 快捷指令通过 shortcuts:// URL scheme 导入
    
    /// 获取微信支付通知捕获快捷指令的安装步骤
    var wechatSetupSteps: [SetupStep] {
        [
            SetupStep(
                step: 1,
                title: "打开「快捷指令」App",
                detail: "在 iPhone 上打开系统自带的「快捷指令」应用",
                icon: "apps.iphone"
            ),
            SetupStep(
                step: 2,
                title: "切换到「自动化」标签",
                detail: "点击底部的「自动化」选项卡",
                icon: "bolt.fill"
            ),
            SetupStep(
                step: 3,
                title: "创建个人自动化",
                detail: "点击右上角「+」→「创建个人自动化」",
                icon: "plus.circle.fill"
            ),
            SetupStep(
                step: 4,
                title: "选择触发条件：App",
                detail: "向下滚动，选择「App」→ 选择「微信」→ 勾选「通知」",
                icon: "bell.badge.fill"
            ),
            SetupStep(
                step: 5,
                title: "添加操作：记账本",
                detail: "搜索「记账本」→ 选择「通知自动记账」→ 将「通知内容」传入",
                icon: "text.badge.plus"
            ),
            SetupStep(
                step: 6,
                title: "关闭「运行前询问」",
                detail: "关闭「运行前询问」开关，这样支付后会完全自动记账",
                icon: "hand.tap.fill"
            ),
        ]
    }
    
    /// 获取支付宝通知捕获快捷指令的安装步骤
    var alipaySetupSteps: [SetupStep] {
        var steps = wechatSetupSteps
        steps[3] = SetupStep(
            step: 4,
            title: "选择触发条件：App",
            detail: "向下滚动，选择「App」→ 选择「支付宝」→ 勾选「通知」",
            icon: "bell.badge.fill"
        )
        return steps
    }
    
    /// 生成一键安装 URL（通过 shortcuts:// 协议导入预制快捷指令）
    /// 注意：实际项目中需要将快捷指令上传到 iCloud 获取共享链接
    func getInstallURL(for channel: PaymentChannel) -> URL? {
        // 使用 URL Scheme 方式：创建一个快捷指令并预填参数
        // shortcuts://create-shortcut 可以创建新的快捷指令
        // 实际部署时，使用 iCloud 共享链接效果更好
        
        switch channel {
        case .wechat:
            // URL 编码的快捷指令名称
            let name = "微信自动记账".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "shortcuts://create-shortcut?name=\(name)")
        case .alipay:
            let name = "支付宝自动记账".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "shortcuts://create-shortcut?name=\(name)")
        default:
            return nil
        }
    }
    
    /// 打开快捷指令 App 的自动化标签页
    func openShortcutsAutomation() {
        if let url = URL(string: "shortcuts://create-automation") {
            UIApplication.shared.open(url)
        }
    }
    
    /// 打开快捷指令 App
    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - 一键配置（通过 URL Scheme 传递参数）
    // 用户在 App 内点击按钮，自动跳转到快捷指令 App 并预填配置
    func installWechatAutomation() {
        // 标记开始安装流程
        UserDefaults.standard.set(true, forKey: "Shortcut.wechat.installing")
        openShortcutsAutomation()
    }
    
    func installAlipayAutomation() {
        UserDefaults.standard.set(true, forKey: "Shortcut.alipay.installing")
        openShortcutsAutomation()
    }
    
    /// 从 App 返回时检查安装状态
    func checkInstallationStatus() {
        // 如果正在安装流程中，假设用户已完成
        if UserDefaults.standard.bool(forKey: "Shortcut.wechat.installing") {
            wechatShortcutInstalled = true
            isWechatAutomationEnabled = true
            UserDefaults.standard.removeObject(forKey: "Shortcut.wechat.installing")
        }
        if UserDefaults.standard.bool(forKey: "Shortcut.alipay.installing") {
            alipayShortcutInstalled = true
            isAlipayAutomationEnabled = true
            UserDefaults.standard.removeObject(forKey: "Shortcut.alipay.installing")
        }
    }
    
    // MARK: - 记录管理
    private func addRecord(_ record: NotificationRecord) {
        recentRecords.insert(record, at: 0)
        if recentRecords.count > maxRecords {
            recentRecords = Array(recentRecords.prefix(maxRecords))
        }
        saveRecords()
        updateTodayStats()
    }
    
    private func updateTodayStats() {
        let today = Calendar.current.startOfDay(for: Date())
        let todayRecords = recentRecords.filter {
            $0.success && Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        todayCaptureCount = todayRecords.count
        todayCaptureAmount = todayRecords.compactMap { $0.parsedAmount }.reduce(0, +)
    }
    
    private func saveRecords() {
        if let data = try? JSONEncoder().encode(recentRecords) {
            UserDefaults.standard.set(data, forKey: "Shortcut.records")
        }
    }
    
    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: "Shortcut.records"),
           let records = try? JSONDecoder().decode([NotificationRecord].self, from: data) {
            recentRecords = records
        }
    }
    
    /// 清除所有记录
    func clearRecords() {
        recentRecords.removeAll()
        saveRecords()
        updateTodayStats()
    }
    
    // MARK: - 状态汇总
    var isAnyAutomationActive: Bool {
        isWechatAutomationEnabled || isAlipayAutomationEnabled
    }
    
    var activeSourceCount: Int {
        (isWechatAutomationEnabled ? 1 : 0) + (isAlipayAutomationEnabled ? 1 : 0)
    }
    
    var statusSummary: String {
        if !isAnyAutomationActive {
            return "未启用通知自动记账"
        }
        var sources: [String] = []
        if isWechatAutomationEnabled { sources.append("微信") }
        if isAlipayAutomationEnabled { sources.append("支付宝") }
        return "\(sources.joined(separator: "、"))通知捕获中"
    }
}

// MARK: - 设置步骤模型
struct SetupStep: Identifiable {
    let id = UUID()
    let step: Int
    let title: String
    let detail: String
    let icon: String
}
