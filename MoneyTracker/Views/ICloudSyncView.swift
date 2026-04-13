import SwiftUI

// MARK: - iCloud 同步设置页
struct ICloudSyncView: View {
    @EnvironmentObject var viewModel: TransactionViewModel
    @ObservedObject private var syncManager = ICloudSyncManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var showSyncConfirm = false
    
    var body: some View {
        List {
            // 状态卡片
            Section {
                statusCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            // 同步开关
            Section {
                Toggle(isOn: $syncManager.autoSyncEnabled) {
                    Label("自动同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Color(hex: "4F46E5"))
            } footer: {
                Text("开启后，每次打开 App 或数据变更时自动与 iCloud 同步。同一 Apple ID 下的所有设备共享数据。")
            }
            
            // 手动操作
            Section("手动同步") {
                // 上传
                Button(action: {
                    syncManager.uploadToCloud(transactions: viewModel.transactions)
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("上传到 iCloud")
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                            Text("将本机 \(viewModel.transactions.count) 条记录上传到云端")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if syncManager.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncManager.isSyncing || !syncManager.iCloudAvailable)
                
                // 下载
                Button(action: {
                    syncManager.downloadFromCloud { cloudTransactions in
                        if !cloudTransactions.isEmpty {
                            showSyncConfirm = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.down.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从 iCloud 下载")
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                            Text("云端有 \(syncManager.cloudRecordCount) 条记录")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if syncManager.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncManager.isSyncing || !syncManager.iCloudAvailable)
                
                // 双向合并
                Button(action: {
                    syncManager.syncWithCloud(localTransactions: viewModel.transactions) { merged in
                        viewModel.replaceAllTransactions(merged)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "4F46E5"))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("双向合并同步")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("合并本地与云端数据，智能去重")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if syncManager.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncManager.isSyncing || !syncManager.iCloudAvailable)
            }
            
            // 同步信息
            Section("同步信息") {
                infoRow(icon: "iphone.gen3", label: "本机记录", value: "\(viewModel.transactions.count) 条")
                infoRow(icon: "icloud", label: "云端记录", value: "\(syncManager.cloudRecordCount) 条")
                infoRow(icon: "clock", label: "上次同步", value: lastSyncText)
                infoRow(icon: "person.crop.circle", label: "Apple ID", value: syncManager.iCloudAvailable ? "已登录" : "未登录")
            }
            
            // 同步日志
            if !syncManager.syncLog.isEmpty {
                Section("同步日志") {
                    ForEach(syncManager.syncLog.reversed(), id: \.self) { entry in
                        Text(entry)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 危险操作
            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("清除 iCloud 数据", systemImage: "trash")
                        Spacer()
                    }
                }
                .disabled(!syncManager.iCloudAvailable)
            } footer: {
                Text("仅删除 iCloud 上的同步数据，不影响本机已有记录。")
            }
        }
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .alert("确认清除", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                syncManager.clearCloudData()
            }
        } message: {
            Text("将删除 iCloud 上所有同步数据，此操作不可撤销。")
        }
        .alert("下载完成", isPresented: $showSyncConfirm) {
            Button("合并导入") {
                syncManager.downloadFromCloud { cloudTxs in
                    viewModel.importTransactions(cloudTxs)
                }
            }
            Button("替换本地数据") {
                syncManager.downloadFromCloud { cloudTxs in
                    viewModel.replaceAllTransactions(cloudTxs)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("云端有 \(syncManager.cloudRecordCount) 条记录。选择合并（保留本地+云端）还是替换（用云端覆盖本地）？")
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudDataDidChange)) { _ in
            if syncManager.autoSyncEnabled {
                syncManager.syncWithCloud(localTransactions: viewModel.transactions) { merged in
                    viewModel.replaceAllTransactions(merged)
                }
            }
        }
    }
    
    // MARK: - 状态卡片
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(syncManager.iCloudAvailable ?
                              Color(hex: "4F46E5").opacity(0.15) :
                              Color.gray.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: syncManager.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                        .font(.system(size: 26))
                        .foregroundColor(syncManager.iCloudAvailable ? Color(hex: "4F46E5") : .gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncManager.iCloudAvailable ? "iCloud 已连接" : "iCloud 未连接")
                        .font(.system(size: 17, weight: .bold))
                    Text(syncManager.iCloudAvailable
                         ? "数据安全存储在你的 iCloud 中"
                         : "请在设置中登录 Apple ID 并开启 iCloud Drive")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            if syncManager.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("同步中...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "4F46E5"))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    private var lastSyncText: String {
        guard let date = syncManager.lastSyncDate else { return "从未同步" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return fmt.string(from: date)
    }
}
