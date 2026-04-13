import SwiftUI

@main
struct MoneyTrackerApp: App {
    @StateObject private var viewModel = TransactionViewModel()

    init() {
        // 注册后台任务
        AutoSyncScheduler.shared.registerBackgroundTasks()
        // 注册通知操作按钮
        LocationTriggerManager.registerNotificationActions()
        // 请求通知权限
        AutoSyncScheduler.shared.requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.performStartupTasks()
                }
                .onOpenURL { url in
                    if url.absoluteString.contains("callback") {
                        ThirdPartyPaySync().handleCallback(url: url)
                    } else if url.host == "notification-record" {
                        // 快捷指令通知记账回调
                        handleNotificationRecordURL(url)
                    } else if let tx = URLSchemeHandler.handleURL(url) {
                        viewModel.addTransaction(tx)
                    }
                }
        }
    }
    
    /// 处理 moneytracker://notification-record?text=xxx&source=微信 回调
    private func handleNotificationRecordURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let params = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        
        guard let text = params["text"] else { return }
        let source = params["source"] ?? "未知"
        
        if let tx = ShortcutAutomationManager.shared.processNotification(text: text, source: source) {
            viewModel.addTransaction(tx)
        }
    }
}
