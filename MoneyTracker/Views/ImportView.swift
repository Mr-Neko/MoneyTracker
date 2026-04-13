import SwiftUI
import UniformTypeIdentifiers

// MARK: - 自动化控制中心（原导入页重构）
struct ImportView: View {
    @EnvironmentObject var viewModel: TransactionViewModel
    @StateObject private var thirdPartySync = ThirdPartyPaySync()
    @ObservedObject private var scheduler = AutoSyncScheduler.shared
    @ObservedObject private var locationManager = LocationTriggerManager.shared
    @ObservedObject private var shortcutManager = ShortcutAutomationManager.shared

    @State private var showFilePicker = false
    @State private var showSMSInput = false
    @State private var showEmailConfig = false
    @State private var showLocationSetup = false
    @State private var showImportResult = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var importResult: CSVParseResult?
    @State private var showWechatSetup = false
    @State private var showAlipaySetup = false
    @State private var showCaptureLog = false
    @State private var showICloudSync = false

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    masterStatusCard
                    notificationCaptureSection
                    dataSourcesSection
                    automationRulesSection
                    manualSection
                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .background(Color(hex: "F5F5F7"))
            .navigationTitle("自动记账")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showFilePicker) { documentPickerSheet }
        .sheet(isPresented: $showSMSInput) { NavigationView { smsInputSheet } }
        .sheet(isPresented: $showEmailConfig) { NavigationView { EmailConfigView(fetcher: EmailBillFetcher()) } }
        .sheet(isPresented: $showLocationSetup) { NavigationView { locationSetupSheet } }
        .sheet(isPresented: $showImportResult) { NavigationView { ImportResultView(result: importResult) } }
        .sheet(isPresented: $showWechatSetup) { NavigationView { ShortcutSetupGuideView(channel: .wechat) } }
        .sheet(isPresented: $showAlipaySetup) { NavigationView { ShortcutSetupGuideView(channel: .alipay) } }
        .sheet(isPresented: $showCaptureLog) { NavigationView { CaptureLogView() } }
        .sheet(isPresented: $showICloudSync) { NavigationView { ICloudSyncView().environmentObject(viewModel) } }
        .alert("提示", isPresented: $showAlert) { Button("确定") {} } message: { Text(alertMessage) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            shortcutManager.checkInstallationStatus()
            viewModel.importPendingShortcutRecords()
        }
    }

    // MARK: - 自动化主状态卡片
    private var masterStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动记账")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    let sourceCount = connectedSourceCount
                    Text(sourceCount > 0 ? "\(sourceCount) 个数据源已连接" : "尚未连接数据源")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Toggle("", isOn: $scheduler.isEnabled)
                    .labelsHidden()
                    .tint(.green)
                    .onChange(of: scheduler.isEnabled) { enabled in
                        if enabled {
                            scheduler.scheduleNextSync()
                            scheduler.requestNotificationPermission()
                        }
                    }
            }

            HStack(spacing: 12) {
                statusPill(icon: "bolt.fill",
                           label: scheduler.isEnabled ? "运行中" : "已暂停",
                           active: scheduler.isEnabled)
                if shortcutManager.isAnyAutomationActive {
                    statusPill(icon: "bell.badge.fill",
                               label: "通知捕获",
                               active: true)
                }
                statusPill(icon: "arrow.triangle.2.circlepath",
                           label: "已记 \(scheduler.backgroundSyncCount + shortcutManager.captureCount)",
                           active: (scheduler.backgroundSyncCount + shortcutManager.captureCount) > 0)
                statusPill(icon: "clock",
                           label: lastSyncText,
                           active: scheduler.lastBackgroundSync != nil || shortcutManager.lastCaptureDate != nil)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: scheduler.isEnabled ?
                    [Color(hex: "10B981"), Color(hex: "059669")] :
                    [Color(hex: "6B7280"), Color(hex: "4B5563")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: (scheduler.isEnabled ? Color(hex: "10B981") : Color.gray).opacity(0.3), radius: 12, y: 6)
    }

    private func statusPill(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(active ? 1 : 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(active ? 0.2 : 0.08))
        .cornerRadius(20)
    }

    // MARK: - ⭐ 通知自动记账（核心功能区）
    private var notificationCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "F59E0B"))
                Text("通知自动记账")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("推荐方案")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "F97316")],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(4)
            }

            // 说明卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "F59E0B"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("利用 iOS 快捷指令自动化")
                            .font(.system(size: 14, weight: .semibold))
                        Text("捕获微信/支付宝支付通知 → 自动解析金额、商户 → 智能分类入账，全程零操作。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                if shortcutManager.todayCaptureCount > 0 {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("今日 \(shortcutManager.todayCaptureCount) 笔")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        Text("¥\(String(format: "%.0f", shortcutManager.todayCaptureAmount))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "4F46E5"))
                        Spacer()
                        Button("查看记录") { showCaptureLog = true }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(10)
                }
            }
            .padding(14)
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

            // 微信
            notificationChannelCard(
                icon: "message.fill",
                title: "微信支付通知",
                subtitle: shortcutManager.isWechatAutomationEnabled
                    ? "运行中 · 已捕获 \(wechatCaptureCountText)"
                    : "每次微信支付后自动记账",
                color: Color(hex: "07C160"),
                isEnabled: $shortcutManager.isWechatAutomationEnabled,
                isInstalled: shortcutManager.wechatShortcutInstalled,
                onSetup: { showWechatSetup = true },
                onToggle: { enabled in
                    if enabled && !shortcutManager.wechatShortcutInstalled {
                        shortcutManager.isWechatAutomationEnabled = false
                        showWechatSetup = true
                    }
                }
            )

            // 支付宝
            notificationChannelCard(
                icon: "a.circle.fill",
                title: "支付宝通知",
                subtitle: shortcutManager.isAlipayAutomationEnabled
                    ? "运行中 · 支付宝消费自动入账"
                    : "每次支付宝付款后自动记账",
                color: Color(hex: "1677FF"),
                isEnabled: $shortcutManager.isAlipayAutomationEnabled,
                isInstalled: shortcutManager.alipayShortcutInstalled,
                onSetup: { showAlipaySetup = true },
                onToggle: { enabled in
                    if enabled && !shortcutManager.alipayShortcutInstalled {
                        shortcutManager.isAlipayAutomationEnabled = false
                        showAlipaySetup = true
                    }
                }
            )
        }
    }

    private var wechatCaptureCountText: String {
        let count = shortcutManager.recentRecords.filter { $0.source.contains("微信") && $0.success }.count
        return "\(count) 笔"
    }

    private func notificationChannelCard(
        icon: String, title: String, subtitle: String, color: Color,
        isEnabled: Binding<Bool>, isInstalled: Bool,
        onSetup: @escaping () -> Void, onToggle: @escaping (Bool) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(isEnabled.wrappedValue ? 1 : 0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isEnabled.wrappedValue ? .white : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isInstalled {
                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .tint(color)
                        .onChange(of: isEnabled.wrappedValue) { newVal in
                            onToggle(newVal)
                        }
                } else {
                    Button("一键配置") { onSetup() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(color)
                        .cornerRadius(10)
                }
            }
            .padding(14)

            // 已配置：显示查看引导入口；未配置：显示提示
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "questionmark.circle" : "info.circle.fill")
                    .font(.system(size: 11))
                Text(isInstalled ? "配置有问题？" : "需配置快捷指令自动化，点击「一键配置」查看引导")
                    .font(.system(size: 11))
                if isInstalled {
                    Button("查看配置流程") { onSetup() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                }
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 数据源连接
    private var dataSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "link", title: "其他数据源", color: Color(hex: "4F46E5"))

            if #available(iOS 17.4, *) {
                dataSourceCard(
                    icon: "wallet.pass.fill", title: "Apple Wallet",
                    subtitle: "自动同步 Apple Pay 和绑定银行卡的所有交易",
                    color: Color(hex: "1D1D1F"),
                    connected: viewModel.financeKitEnabled,
                    badge: "零操作"
                ) {
                    Task { await viewModel.setupFinanceKit() }
                }
            }

            dataSourceCard(
                icon: "envelope.fill", title: "邮箱自动拉取",
                subtitle: "自动下载邮箱中的微信/支付宝导出账单",
                color: Color(hex: "F59E0B"),
                connected: false,
                badge: nil
            ) {
                showEmailConfig = true
            }

            dataSourceCard(
                icon: "icloud.fill", title: "iCloud 同步",
                subtitle: ICloudSyncManager.shared.iCloudAvailable
                    ? "已连接 · \(ICloudSyncManager.shared.cloudRecordCount) 条云端记录"
                    : "同一 Apple ID 多设备同步数据",
                color: Color(hex: "007AFF"),
                connected: ICloudSyncManager.shared.iCloudAvailable && ICloudSyncManager.shared.autoSyncEnabled,
                badge: "多设备"
            ) {
                showICloudSync = true
            }
        }
    }

    private func dataSourceCard(icon: String, title: String, subtitle: String, color: Color,
                                connected: Bool, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(connected ? 1 : 0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(connected ? .white : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "10B981"))
                                .cornerRadius(4)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if connected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                } else {
                    Text("连接")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(color)
                        .cornerRadius(8)
                }
            }
            .padding(14)
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    // MARK: - 自动化规则
    private var automationRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "gearshape.2.fill", title: "自动化规则", color: Color(hex: "8B5CF6"))

            VStack(spacing: 0) {
                ruleRow(icon: "clock.arrow.circlepath", title: "后台同步频率") {
                    Picker("", selection: $scheduler.syncInterval) {
                        ForEach(SyncInterval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color(hex: "4F46E5"))
                }

                Divider().padding(.leading, 52)

                ruleRow(icon: "bell.badge.fill", title: "新交易通知") {
                    Toggle("", isOn: $scheduler.notifyOnNewTransaction)
                        .labelsHidden()
                        .tint(Color(hex: "4F46E5"))
                }

                Divider().padding(.leading, 52)

                ruleRow(icon: "location.fill", title: "地点自动记账") {
                    HStack(spacing: 8) {
                        if locationManager.isEnabled {
                            Text("\(locationManager.savedPlaces.count) 个地点")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Button(locationManager.isEnabled ? "管理" : "设置") {
                            showLocationSetup = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "4F46E5"))
                    }
                }

                Divider().padding(.leading, 52)

                ruleRow(icon: "tag.fill", title: "AI 智能分类") {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("已启用")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    }
                }

                Divider().padding(.leading, 52)

                ruleRow(icon: "doc.on.doc.fill", title: "自动去重") {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("已启用")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private func ruleRow<Content: View>(icon: String, title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "4F46E5"))
                .frame(width: 28)

            Text(title)
                .font(.system(size: 15))

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 手动补录
    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "hand.tap.fill", title: "手动补录", color: Color(hex: "6B7280"))

            HStack(spacing: 12) {
                manualButton(icon: "doc.text.fill", title: "CSV文件", color: .blue) {
                    showFilePicker = true
                }
                manualButton(icon: "doc.on.clipboard", title: "粘贴短信", color: .purple) {
                    showSMSInput = true
                }
            }

            if !thirdPartySync.syncLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同步日志")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(thirdPartySync.syncLog.suffix(5)) { entry in
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    private func manualButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.white)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    // MARK: - Sheets
    private var documentPickerSheet: some View {
        DocumentPickerView { urls in
            guard let url = urls.first else { return }
            BillStorageManager.shared.importFromURL(url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (parseResult, _)):
                        self.importResult = parseResult
                        viewModel.importTransactions(parseResult.transactions)
                        self.showImportResult = true
                    case .failure(let error):
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        }
    }

    private var smsInputSheet: some View {
        SMSInputView { result in
            importResult = result
            viewModel.importTransactions(result.transactions)
            showSMSInput = false
            showImportResult = true
        }
    }

    private var locationSetupSheet: some View {
        LocationSetupView()
    }

    // MARK: - Helpers
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 15, weight: .bold))
        }
    }

    private var connectedSourceCount: Int {
        var count = 0
        if viewModel.financeKitEnabled { count += 1 }
        if shortcutManager.isWechatAutomationEnabled { count += 1 }
        if shortcutManager.isAlipayAutomationEnabled { count += 1 }
        return count
    }

    private var lastSyncText: String {
        // 取最近的同步时间
        let dates = [scheduler.lastBackgroundSync, shortcutManager.lastCaptureDate].compactMap { $0 }
        guard let latest = dates.max() else { return "未同步" }
        let interval = Date().timeIntervalSince(latest)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        return "\(Int(interval / 3600))小时前"
    }
}

// MARK: - 快捷指令配置引导页
struct ShortcutSetupGuideView: View {
    let channel: PaymentChannel
    @ObservedObject private var manager = ShortcutAutomationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private var steps: [SetupStep] {
        channel == .wechat ? manager.wechatSetupSteps : manager.alipaySetupSteps
    }

    private var channelName: String {
        channel == .wechat ? "微信" : "支付宝"
    }

    private var channelColor: Color {
        channel == .wechat ? Color(hex: "07C160") : Color(hex: "1677FF")
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(channelColor.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: channel == .wechat ? "message.fill" : "a.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(channelColor)
                }

                Text("\(channelName)支付通知自动记账")
                    .font(.system(size: 20, weight: .bold))

                Text("配置后，每次\(channelName)支付完成，系统自动捕获通知并记账")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // 步骤列表
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            // 步骤编号 + 连接线
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(index <= currentStep ? channelColor : Color.gray.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    if index < currentStep {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(step.step)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(index == currentStep ? .white : .gray)
                                    }
                                }

                                if index < steps.count - 1 {
                                    Rectangle()
                                        .fill(index < currentStep ? channelColor.opacity(0.3) : Color.gray.opacity(0.15))
                                        .frame(width: 2, height: 40)
                                }
                            }

                            // 步骤内容
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: step.icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(channelColor)
                                    Text(step.title)
                                        .font(.system(size: 15, weight: .semibold))
                                }

                                Text(step.detail)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                currentStep = index
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // 底部操作
            VStack(spacing: 12) {
                Button(action: {
                    if channel == .wechat {
                        manager.installWechatAutomation()
                    } else {
                        manager.installAlipayAutomation()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("打开快捷指令 App 配置")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(channelColor)
                    .cornerRadius(14)
                }

                Button(action: {
                    if channel == .wechat {
                        manager.wechatShortcutInstalled = true
                        manager.isWechatAutomationEnabled = true
                    } else {
                        manager.alipayShortcutInstalled = true
                        manager.isAlipayAutomationEnabled = true
                    }
                    dismiss()
                }) {
                    Text("我已完成配置")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(channelColor)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .navigationTitle("配置\(channelName)自动记账")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
    }
}

// MARK: - 捕获记录日志
struct CaptureLogView: View {
    @ObservedObject private var manager = ShortcutAutomationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总捕获")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(manager.captureCount)")
                            .font(.system(size: 24, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(manager.todayCaptureCount)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日金额")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("¥\(String(format: "%.0f", manager.todayCaptureAmount))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                }
                .padding(.vertical, 8)
            }

            Section("最近捕获记录") {
                if manager.recentRecords.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("暂无记录")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("配置快捷指令自动化后，支付记录将自动出现在这里")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    ForEach(manager.recentRecords) { record in
                        HStack(spacing: 12) {
                            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(record.success ? .green : .red)
                                .font(.system(size: 16))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(record.source)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let amount = record.parsedAmount {
                                        Text("¥\(String(format: "%.2f", amount))")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(Color(hex: "4F46E5"))
                                    }
                                    if let merchant = record.parsedMerchant, !merchant.isEmpty {
                                        Text(merchant)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text(record.rawText.prefix(60) + (record.rawText.count > 60 ? "..." : ""))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Text(timeAgoText(record.date))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !manager.recentRecords.isEmpty {
                Section {
                    Button(role: .destructive) {
                        manager.clearRecords()
                    } label: {
                        HStack {
                            Spacer()
                            Text("清除所有记录")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("捕获记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func timeAgoText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}

// MARK: - 地点设置页
struct LocationSetupView: View {
    @ObservedObject private var manager = LocationTriggerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Toggle("启用地点自动记账", isOn: $manager.isEnabled)
                    .onChange(of: manager.isEnabled) { enabled in
                        if enabled {
                            manager.startAllMonitoring()
                        } else {
                            manager.stopAllMonitoring()
                        }
                    }
            } footer: {
                Text("当你进入已设置的消费地点时，自动弹出记账通知。设置了常用金额的地点，离开时会自动记账。")
            }

            Section("已保存的地点（\(manager.savedPlaces.count)/20）") {
                if manager.savedPlaces.isEmpty {
                    Text("暂无地点，点击下方添加")
                        .foregroundColor(.secondary)
                }
                ForEach(manager.savedPlaces) { place in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(.system(size: 15, weight: .medium))
                            HStack(spacing: 8) {
                                Text(place.defaultCategory.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if let amt = place.typicalAmount {
                                    Text("¥\(String(format: "%.0f", amt))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color(hex: "4F46E5"))
                                }
                                if place.autoRecord {
                                    Text("自动记")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.green)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        Spacer()
                        Text("\(Int(place.radius))m")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        manager.removePlace(manager.savedPlaces[i])
                    }
                }
            }

            Section("快速添加模板") {
                ForEach(LocationTriggerManager.placeTemplates, id: \.name) { template in
                    Button(action: {
                        let place = SavedPlace(
                            name: template.name,
                            latitude: 39.9042 + Double.random(in: -0.05...0.05),
                            longitude: 116.4074 + Double.random(in: -0.05...0.05),
                            radius: template.radius,
                            defaultCategory: template.category,
                            defaultChannel: template.channel
                        )
                        manager.addPlace(place)
                    }) {
                        HStack {
                            Image(systemName: template.category.icon)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(template.name)
                            Spacer()
                            Text(template.category.rawValue)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .navigationTitle("地点自动记账")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}
