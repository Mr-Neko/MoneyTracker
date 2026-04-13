import Foundation

// MARK: - 邮箱账单自动拉取服务
// 微信/支付宝导出的账单会发送到用户邮箱，本服务通过 IMAP 自动拉取附件
class EmailBillFetcher: ObservableObject {

    @Published var config: EmailConfig
    @Published var fetchStatus: FetchStatus = .idle
    @Published var lastFetchDate: Date?
    @Published var fetchLog: [FetchLogEntry] = []

    // 持久化 Key
    private let configKey = "EmailBillFetcher.config"
    private let lastFetchKey = "EmailBillFetcher.lastFetch"

    init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let saved = try? JSONDecoder().decode(EmailConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = EmailConfig()
        }
        self.lastFetchDate = UserDefaults.standard.object(forKey: lastFetchKey) as? Date
    }

    // MARK: - 保存配置
    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    // MARK: - 执行拉取
    // 在真实项目中，这里会使用 MailCore2 等 IMAP 库
    // Demo 中模拟拉取流程，展示完整的交互逻辑
    func fetchBills(completion: @escaping (Result<[CSVParseResult], Error>) -> Void) {
        guard config.isValid else {
            completion(.failure(BillError.emailConfigMissing))
            return
        }

        fetchStatus = .fetching
        addLog("开始连接邮箱 \(config.email)...")

        // 模拟异步网络请求
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Step 1: 连接 IMAP
            self.addLog("正在通过 IMAP 连接 \(self.config.imapServer):\(self.config.imapPort)...")
            Thread.sleep(forTimeInterval: 1.0)

            // Step 2: 搜索账单邮件
            let searchQueries = [
                "微信支付 账单",
                "支付宝 交易流水",
                "银行 电子对账单",
            ]
            self.addLog("搜索关键词: \(searchQueries.joined(separator: ", "))")
            Thread.sleep(forTimeInterval: 0.8)

            // Step 3: 过滤时间范围（半年内）
            let calendar = Calendar.current
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date())!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            self.addLog("时间范围: \(dateFormatter.string(from: sixMonthsAgo)) ~ 今天")
            Thread.sleep(forTimeInterval: 0.5)

            // 模拟找到邮件
            let foundCount = Int.random(in: 0...3)
            self.addLog("找到 \(foundCount) 封包含账单附件的邮件")

            if foundCount == 0 {
                DispatchQueue.main.async {
                    self.fetchStatus = .completed(count: 0)
                    self.lastFetchDate = Date()
                    UserDefaults.standard.set(Date(), forKey: self.lastFetchKey)
                    self.addLog("✅ 未发现新账单，可能已全部导入")
                    completion(.success([]))
                }
                return
            }

            // Step 4: 下载附件并解析
            var results: [CSVParseResult] = []
            self.addLog("开始下载附件...")

            // 生成模拟的CSV数据
            let mockCSVs = self.generateMockEmailCSVs(count: foundCount)

            for (index, (fileName, csvContent, source)) in mockCSVs.enumerated() {
                Thread.sleep(forTimeInterval: 0.5)
                self.addLog("[\(index+1)/\(foundCount)] 下载: \(fileName)")

                let result = CSVParser.autoParseCSV(content: csvContent)
                results.append(result)

                // 保存到 temp 归档
                if let data = csvContent.data(using: .utf8) {
                    BillStorageManager.shared.archiveCSVFile(
                        data: data, source: source,
                        originalFileName: fileName, parseResult: result
                    )
                }
                self.addLog("  → 解析成功: \(result.successCount) 条记录")
            }

            DispatchQueue.main.async {
                let totalRecords = results.reduce(0) { $0 + $1.successCount }
                self.fetchStatus = .completed(count: totalRecords)
                self.lastFetchDate = Date()
                UserDefaults.standard.set(Date(), forKey: self.lastFetchKey)
                self.addLog("✅ 拉取完成! 共 \(totalRecords) 条新记录")
                completion(.success(results))
            }
        }
    }

    // MARK: - 模拟邮箱中的CSV数据
    private func generateMockEmailCSVs(count: Int) -> [(String, String, CSVSource)] {
        var csvs: [(String, String, CSVSource)] = []
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if count >= 1 {
            // 微信账单
            var wechatCSV = """
            微信支付账单明细
            微信昵称：[用户]
            起始时间：[2026-03-01 00:00:00] 终止时间：[2026-03-31 23:59:59]
            导出类型：[全部]
            导出时间：[2026-04-01 10:00:00]

            共\(Int.random(in: 30...80))笔交易

            收入：5笔 2300.00元
            支出：45笔 6850.50元

            资金流入：2300.00元
            资金流出：6850.50元

            ---以下为交易明细---
            ----------------------微信支付账单明细列表--------------------
            交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n
            """
            let merchants = [
                ("美团外卖", "外卖-黄焖鸡米饭", 28.5), ("瑞幸咖啡", "拿铁咖啡", 15.0),
                ("滴滴出行", "快车", 23.0), ("盒马鲜生", "日用品采购", 156.8),
                ("星巴克", "美式咖啡", 32.0), ("全家便利店", "零食饮料", 18.5),
            ]
            for i in 0..<6 {
                let date = calendar.date(byAdding: .day, value: -(i * 3 + 25), to: now)!
                let m = merchants[i]
                wechatCSV += "\(dateFormatter.string(from: date)),商户消费,\(m.0),\(m.1),支出,¥\(m.2),零钱通,支付成功,T00\(i),M00\(i),\"\"\n"
            }
            csvs.append(("微信支付账单_202603.csv", wechatCSV, .wechat))
        }

        if count >= 2 {
            // 支付宝账单
            var alipayCSV = """
            支付宝交易记录明细查询
            账号：[user@example.com]
            起始日期：[2026-03-01 00:00:00]    终止日期：[2026-03-31 23:59:59]
            交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注\n
            """
            let items = [
                ("淘宝", "连衣裙春季新款", 189.0), ("饿了么", "午餐-麻辣烫", 22.0),
                ("高德地图", "打车费用", 35.5), ("京东", "办公用品", 68.0),
                ("哈啰单车", "骑行费", 3.5),
            ]
            for (i, item) in items.enumerated() {
                let date = calendar.date(byAdding: .day, value: -(i * 4 + 22), to: now)!
                alipayCSV += "202603\(String(format: "%05d", i)),ORD\(i),\(dateFormatter.string(from: date)),\(dateFormatter.string(from: date)),\(dateFormatter.string(from: date)),其他,即时到账交易,\(item.0),\(item.1),\(item.2),支出,交易成功,0,0,\n"
            }
            alipayCSV += "------------------------------------------------------------------------------------\n"
            csvs.append(("alipay_record_202603.csv", alipayCSV, .alipay))
        }

        if count >= 3 {
            // 银行对账单
            var bankCSV = "交易日期,交易摘要,交易金额,余额,交易对方\n"
            let bankItems = [
                ("工资", 15800.0, "XX公司"), ("房租", -3200.0, "房东张三"),
                ("水电费", -350.0, "物业公司"), ("ATM取款", -500.0, ""),
            ]
            for (i, item) in bankItems.enumerated() {
                let date = calendar.date(byAdding: .day, value: -(i * 7 + 20), to: now)!
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd"
                bankCSV += "\(df.string(from: date)),\(item.0),\(item.1),50000.00,\(item.2)\n"
            }
            csvs.append(("招商银行对账单_202603.csv", bankCSV, .bankCMB))
        }

        return csvs
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.fetchLog.append(FetchLogEntry(message: message))
        }
    }
}

// MARK: - 邮箱配置
struct EmailConfig: Codable {
    var email: String = ""
    var password: String = ""   // 授权码，非登录密码
    var imapServer: String = ""
    var imapPort: Int = 993
    var useSSL: Bool = true
    var autoFetchEnabled: Bool = false
    var autoFetchIntervalHours: Int = 24

    var isValid: Bool {
        !email.isEmpty && !password.isEmpty && !imapServer.isEmpty
    }

    // 常见邮箱预设
    static let presets: [(name: String, server: String, port: Int)] = [
        ("QQ邮箱", "imap.qq.com", 993),
        ("163邮箱", "imap.163.com", 993),
        ("126邮箱", "imap.126.com", 993),
        ("Gmail", "imap.gmail.com", 993),
        ("Outlook", "outlook.office365.com", 993),
        ("腾讯企业邮", "imap.exmail.qq.com", 993),
    ]

    mutating func applyPreset(_ preset: (name: String, server: String, port: Int)) {
        imapServer = preset.server
        imapPort = preset.port
        useSSL = true
    }
}

// MARK: - 拉取状态
enum FetchStatus: Equatable {
    case idle
    case fetching
    case completed(count: Int)
    case error(String)

    static func == (lhs: FetchStatus, rhs: FetchStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.fetching, .fetching): return true
        case (.completed(let a), .completed(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - 日志条目
struct FetchLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}
