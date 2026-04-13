import Foundation

// MARK: - 本地账单文件管理器
// 管理 Documents/BillArchive/ 目录，自动维护半年内的CSV账单文件
class BillStorageManager {

    static let shared = BillStorageManager()

    // 存储根目录
    private let archiveDirName = "BillArchive"
    // 导入记录持久化文件
    private let recordsFileName = "import_records.json"
    // 保留月数
    private let retentionMonths = 6

    private init() {
        createDirectoryIfNeeded()
    }

    // MARK: - 目录结构
    // Documents/BillArchive/
    //   ├── wechat/
    //   │   ├── 2026-04_微信账单.csv
    //   │   └── 2026-03_微信账单.csv
    //   ├── alipay/
    //   │   └── 2026-04_支付宝账单.csv
    //   ├── bank/
    //   │   └── 2026-04_招商银行.csv
    //   └── import_records.json

    var archiveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(archiveDirName)
    }

    // MARK: - 保存导入的CSV文件到 temp 归档
    @discardableResult
    func archiveCSVFile(data: Data, source: CSVSource, originalFileName: String, parseResult: CSVParseResult) -> ImportRecord? {
        let subDir = subdirectory(for: source)
        let dirURL = archiveDirectory.appendingPathComponent(subDir)

        // 创建子目录
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // 生成文件名: 2026-04_微信账单_20260410153000.csv
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let monthStr = dateFormatter.string(from: Date())
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let sanitizedName = originalFileName
            .replacingOccurrences(of: ".csv", with: "")
            .replacingOccurrences(of: "/", with: "_")

        let fileName = "\(monthStr)_\(sanitizedName)_\(timestamp).csv"
        let fileURL = dirURL.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
        } catch {
            print("❌ 保存CSV失败: \(error)")
            return nil
        }

        // 创建导入记录
        let relativePath = "\(subDir)/\(fileName)"
        let record = ImportRecord(
            source: source,
            fileName: originalFileName,
            recordCount: parseResult.successCount,
            dateRange: parseResult.dateRange,
            filePath: relativePath
        )

        // 保存记录
        var records = loadImportRecords()
        records.append(record)
        saveImportRecords(records)

        // 触发清理
        cleanupExpiredFiles()

        return record
    }

    // MARK: - 从 URL 导入文件（系统文件选择器 / Share Extension）
    func importFromURL(_ url: URL, completion: @escaping (Result<(CSVParseResult, ImportRecord), Error>) -> Void) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                completion(.failure(BillError.encodingFailed))
                return
            }

            let result = CSVParser.autoParseCSV(content: content)

            guard result.successCount > 0 else {
                completion(.failure(BillError.noValidRecords(errors: result.errors)))
                return
            }

            if let record = archiveCSVFile(data: data, source: result.source,
                                           originalFileName: url.lastPathComponent, parseResult: result) {
                completion(.success((result, record)))
            } else {
                completion(.failure(BillError.saveFailed))
            }
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - 查询已归档的文件
    func listArchivedFiles() -> [ArchivedFile] {
        var files: [ArchivedFile] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: archiveDirectory,
                                             includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                                             options: [.skipsHiddenFiles]) else { return files }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "csv" else { continue }

            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? Int64 ?? 0
            let created = attrs?[.creationDate] as? Date ?? Date()

            let relativePath = url.path.replacingOccurrences(of: archiveDirectory.path + "/", with: "")
            let source = detectSourceFromPath(relativePath)

            files.append(ArchivedFile(
                url: url,
                relativePath: relativePath,
                fileName: url.lastPathComponent,
                source: source,
                fileSize: size,
                createdDate: created
            ))
        }

        return files.sorted { $0.createdDate > $1.createdDate }
    }

    // MARK: - 存储空间统计
    func storageStats() -> StorageStats {
        let files = listArchivedFiles()
        let totalSize = files.reduce(0) { $0 + $1.fileSize }
        let records = loadImportRecords()

        var bySource: [CSVSource: Int] = [:]
        for f in files {
            bySource[f.source, default: 0] += 1
        }

        return StorageStats(
            totalFiles: files.count,
            totalSize: totalSize,
            totalRecords: records.reduce(0) { $0 + $1.recordCount },
            bySource: bySource,
            oldestFile: files.last?.createdDate,
            newestFile: files.first?.createdDate
        )
    }

    // MARK: - 半年自动清理
    func cleanupExpiredFiles() {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .month, value: -retentionMonths, to: Date()) else { return }

        let fm = FileManager.default
        let files = listArchivedFiles()
        var removedCount = 0

        for file in files {
            if file.createdDate < cutoffDate {
                try? fm.removeItem(at: file.url)
                removedCount += 1
            }
        }

        // 清理对应的 import records
        if removedCount > 0 {
            var records = loadImportRecords()
            records.removeAll { $0.importDate < cutoffDate }
            saveImportRecords(records)
            print("🧹 已清理 \(removedCount) 个过期账单文件（超过\(retentionMonths)个月）")
        }
    }

    // MARK: - 手动删除单个文件
    func deleteArchivedFile(_ file: ArchivedFile) {
        try? FileManager.default.removeItem(at: file.url)
        var records = loadImportRecords()
        records.removeAll { $0.filePath == file.relativePath }
        saveImportRecords(records)
    }

    // MARK: - 清空全部
    func clearAll() {
        try? FileManager.default.removeItem(at: archiveDirectory)
        createDirectoryIfNeeded()
    }

    // MARK: - Import Records 持久化
    func loadImportRecords() -> [ImportRecord] {
        let url = archiveDirectory.appendingPathComponent(recordsFileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ImportRecord].self, from: data)) ?? []
    }

    private func saveImportRecords(_ records: [ImportRecord]) {
        let url = archiveDirectory.appendingPathComponent(recordsFileName)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url)
        }
    }

    // MARK: - Private Helpers
    private func createDirectoryIfNeeded() {
        let dirs = ["wechat", "alipay", "bank", "sms"]
        for dir in dirs {
            let url = archiveDirectory.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func subdirectory(for source: CSVSource) -> String {
        switch source {
        case .wechat: return "wechat"
        case .alipay: return "alipay"
        case .smsClipboard: return "sms"
        default: return "bank"
        }
    }

    private func detectSourceFromPath(_ path: String) -> CSVSource {
        if path.hasPrefix("wechat") { return .wechat }
        if path.hasPrefix("alipay") { return .alipay }
        if path.hasPrefix("sms") { return .smsClipboard }
        return .bankGeneric
    }
}

// MARK: - 归档文件模型
struct ArchivedFile: Identifiable {
    var id: String { relativePath }
    let url: URL
    let relativePath: String
    let fileName: String
    let source: CSVSource
    let fileSize: Int64
    let createdDate: Date

    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - 存储统计
struct StorageStats {
    let totalFiles: Int
    let totalSize: Int64
    let totalRecords: Int
    let bySource: [CSVSource: Int]
    let oldestFile: Date?
    let newestFile: Date?

    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - 错误类型
enum BillError: LocalizedError {
    case encodingFailed
    case noValidRecords(errors: [String])
    case saveFailed
    case emailConfigMissing
    case emailFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "文件编码无法识别"
        case .noValidRecords(let errors): return "未解析出有效记录\(errors.isEmpty ? "" : "：\(errors.first ?? "")")"
        case .saveFailed: return "文件保存失败"
        case .emailConfigMissing: return "请先配置邮箱信息"
        case .emailFetchFailed(let msg): return "邮箱拉取失败：\(msg)"
        }
    }
}
