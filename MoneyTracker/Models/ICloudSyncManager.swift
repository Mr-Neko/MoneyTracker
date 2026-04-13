import Foundation
import UIKit

// MARK: - iCloud 同步管理器
// 使用 iCloud Documents (UIDocument / FileManager ubiquityContainer) 实现跨设备同步
// 数据以 JSON 文件存储在 iCloud Drive 的独立文件夹中
// 同一 Apple ID 的所有设备自动同步

class ICloudSyncManager: ObservableObject {
    
    static let shared = ICloudSyncManager()
    
    // MARK: - 状态
    @Published var iCloudAvailable = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncLog: [String] = []
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: "iCloud.autoSync") }
    }
    @Published var deviceCount: Int = 0
    @Published var cloudRecordCount: Int = 0
    
    private let containerID: String? = nil // nil = 默认容器
    private let folderName = "MoneyTrackerData"
    private let transactionsFile = "transactions.json"
    private let metadataFile = "sync_metadata.json"
    
    private var metadataQuery: NSMetadataQuery?
    
    private init() {
        autoSyncEnabled = UserDefaults.standard.object(forKey: "iCloud.autoSync") as? Bool ?? true
        lastSyncDate = UserDefaults.standard.object(forKey: "iCloud.lastSync") as? Date
        checkAvailability()
    }
    
    // MARK: - 检查 iCloud 可用性
    func checkAvailability() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let available = FileManager.default.ubiquityIdentityToken != nil
            DispatchQueue.main.async {
                self?.iCloudAvailable = available
                if available {
                    self?.addLog("☁️ iCloud 可用")
                    self?.setupICloudFolder()
                } else {
                    self?.addLog("⚠️ iCloud 不可用，请检查是否登录 Apple ID 并开启 iCloud Drive")
                }
            }
        }
    }
    
    // MARK: - 初始化 iCloud 文件夹
    private func setupICloudFolder() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: self.containerID) else {
                DispatchQueue.main.async {
                    self.iCloudAvailable = false
                    self.addLog("❌ 无法获取 iCloud 容器")
                }
                return
            }
            
            let folderURL = containerURL.appendingPathComponent("Documents").appendingPathComponent(self.folderName)
            
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                do {
                    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    DispatchQueue.main.async {
                        self.addLog("📁 已创建 iCloud 同步文件夹")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.addLog("❌ 创建文件夹失败: \(error.localizedDescription)")
                    }
                }
            }
            
            // 启动文件变更监听
            DispatchQueue.main.async {
                self.startMonitoring()
                self.loadCloudMetadata()
            }
        }
    }
    
    // MARK: - iCloud 文件夹路径
    private var iCloudFolderURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        return containerURL.appendingPathComponent("Documents").appendingPathComponent(folderName)
    }
    
    private var transactionsURL: URL? {
        iCloudFolderURL?.appendingPathComponent(transactionsFile)
    }
    
    private var metadataURL: URL? {
        iCloudFolderURL?.appendingPathComponent(metadataFile)
    }
    
    // MARK: - 上传到 iCloud
    func uploadToCloud(transactions: [Transaction]) {
        guard iCloudAvailable, let fileURL = transactionsURL else {
            addLog("❌ iCloud 不可用，无法上传")
            return
        }
        
        isSyncing = true
        addLog("⬆️ 正在上传 \(transactions.count) 条记录到 iCloud...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(transactions)
                try data.write(to: fileURL, options: .atomic)
                
                // 更新元数据
                let metadata = SyncMetadata(
                    lastSyncDate: Date(),
                    recordCount: transactions.count,
                    deviceName: UIDevice.current.name,
                    deviceModel: UIDevice.current.model,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
                let metaData = try JSONEncoder().encode(metadata)
                if let metaURL = self.metadataURL {
                    try metaData.write(to: metaURL, options: .atomic)
                }
                
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.lastSyncDate = Date()
                    self.cloudRecordCount = transactions.count
                    UserDefaults.standard.set(Date(), forKey: "iCloud.lastSync")
                    self.addLog("✅ 上传成功：\(transactions.count) 条记录")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.addLog("❌ 上传失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 从 iCloud 下载
    func downloadFromCloud(completion: @escaping ([Transaction]) -> Void) {
        guard iCloudAvailable, let fileURL = transactionsURL else {
            addLog("❌ iCloud 不可用，无法下载")
            completion([])
            return
        }
        
        isSyncing = true
        addLog("⬇️ 正在从 iCloud 下载数据...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 触发 iCloud 下载（文件可能还在云端未下载到本地）
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.addLog("⚠️ 触发下载失败: \(error.localizedDescription)")
                    completion([])
                }
                return
            }
            
            // 等待文件下载完成（最多 15 秒）
            var attempts = 0
            while attempts < 30 {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                       let status = resourceValues.ubiquitousItemDownloadingStatus,
                       status == .current {
                        break
                    }
                }
                Thread.sleep(forTimeInterval: 0.5)
                attempts += 1
            }
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.addLog("📭 iCloud 上暂无同步数据")
                    completion([])
                }
                return
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                let transactions = try JSONDecoder().decode([Transaction].self, from: data)
                
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.lastSyncDate = Date()
                    self.cloudRecordCount = transactions.count
                    UserDefaults.standard.set(Date(), forKey: "iCloud.lastSync")
                    self.addLog("✅ 下载成功：\(transactions.count) 条记录")
                    completion(transactions)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.addLog("❌ 解析失败: \(error.localizedDescription)")
                    completion([])
                }
            }
        }
    }
    
    // MARK: - 合并同步（智能去重）
    func syncWithCloud(localTransactions: [Transaction], completion: @escaping ([Transaction]) -> Void) {
        guard iCloudAvailable else {
            addLog("❌ iCloud 不可用")
            completion(localTransactions)
            return
        }
        
        isSyncing = true
        addLog("🔄 开始双向同步...")
        
        downloadFromCloud { [weak self] cloudTransactions in
            guard let self = self else { return }
            
            // 合并：以 id 为准去重，保留最新的
            var mergedMap: [UUID: Transaction] = [:]
            
            for tx in cloudTransactions {
                mergedMap[tx.id] = tx
            }
            for tx in localTransactions {
                mergedMap[tx.id] = tx // 本地优先覆盖
            }
            
            let merged = Array(mergedMap.values).sorted { $0.date > $1.date }
            let cloudOnly = merged.count - localTransactions.count
            
            self.addLog("🔀 合并完成：本地 \(localTransactions.count) + 云端独有 \(max(0, cloudOnly)) = \(merged.count) 条")
            
            // 上传合并结果
            self.uploadToCloud(transactions: merged)
            
            completion(merged)
        }
    }
    
    // MARK: - 监听 iCloud 文件变更
    private func startMonitoring() {
        metadataQuery?.stop()
        
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, transactionsFile)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: query
        )
        
        query.start()
        metadataQuery = query
    }
    
    @objc private func queryDidUpdate(_ notification: Notification) {
        guard autoSyncEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.addLog("📡 检测到 iCloud 数据变更")
            // 通知 ViewModel 有新数据可用
            NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
        }
    }
    
    // MARK: - 读取云端元数据
    private func loadCloudMetadata() {
        guard let metaURL = metadataURL, FileManager.default.fileExists(atPath: metaURL.path) else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: metaURL)
                Thread.sleep(forTimeInterval: 1)
                
                let data = try Data(contentsOf: metaURL)
                let metadata = try JSONDecoder().decode(SyncMetadata.self, from: data)
                
                DispatchQueue.main.async {
                    self?.cloudRecordCount = metadata.recordCount
                    self?.addLog("📊 云端数据：\(metadata.recordCount) 条，来自 \(metadata.deviceName)")
                }
            } catch {
                // 静默失败
            }
        }
    }
    
    // MARK: - 清除云端数据
    func clearCloudData() {
        guard let folderURL = iCloudFolderURL else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            cloudRecordCount = 0
            addLog("🗑️ 已清除 iCloud 上的所有同步数据")
        } catch {
            addLog("❌ 清除失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    private func addLog(_ message: String) {
        let entry = "[\(formatTime(Date()))] \(message)"
        syncLog.append(entry)
        if syncLog.count > 50 { syncLog.removeFirst() }
    }
    
    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

// MARK: - 同步元数据
struct SyncMetadata: Codable {
    let lastSyncDate: Date
    let recordCount: Int
    let deviceName: String
    let deviceModel: String
    let appVersion: String
}

// MARK: - 通知名
extension Notification.Name {
    static let iCloudDataDidChange = Notification.Name("iCloudDataDidChange")
}
