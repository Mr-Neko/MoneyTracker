import Foundation

// MARK: - CSV 导入来源
enum CSVSource: String, Codable, CaseIterable, Identifiable {
    case wechat = "微信"
    case alipay = "支付宝"
    case bankICBC = "工商银行"
    case bankCMB = "招商银行"
    case bankCCB = "建设银行"
    case bankGeneric = "通用银行"
    case smsClipboard = "短信粘贴"
    case unknown = "未识别"

    var id: String { rawValue }
}

// MARK: - 导入记录（追踪每次导入）
struct ImportRecord: Identifiable, Codable {
    let id: UUID
    let source: CSVSource
    let fileName: String
    let importDate: Date
    let recordCount: Int
    let dateRange: String
    let filePath: String  // temp 目录下的相对路径

    init(id: UUID = UUID(), source: CSVSource, fileName: String, importDate: Date = Date(),
         recordCount: Int, dateRange: String, filePath: String) {
        self.id = id
        self.source = source
        self.fileName = fileName
        self.importDate = importDate
        self.recordCount = recordCount
        self.dateRange = dateRange
        self.filePath = filePath
    }
}

// MARK: - CSV 解析结果
struct CSVParseResult {
    let source: CSVSource
    let transactions: [Transaction]
    let skippedRows: Int
    let errors: [String]
    let dateRange: String

    var successCount: Int { transactions.count }
    var totalRows: Int { transactions.count + skippedRows }
}

// MARK: - CSV 解析引擎
class CSVParser {

    // MARK: - 自动检测来源并解析
    static func autoParseCSV(content: String) -> CSVParseResult {
        let source = detectSource(content: content)
        switch source {
        case .wechat:
            return parseWechatCSV(content: content)
        case .alipay:
            return parseAlipayCSV(content: content)
        case .bankCMB:
            return parseCMBCSV(content: content)
        case .smsClipboard:
            return parseSMSText(content: content)
        default:
            return parseGenericCSV(content: content)
        }
    }

    // MARK: - 来源检测
    static func detectSource(content: String) -> CSVSource {
        let header = String(content.prefix(500)).lowercased()

        if header.contains("微信支付账单") || header.contains("微信支付") && header.contains("交易时间") {
            return .wechat
        }
        if header.contains("支付宝") || header.contains("alipay") || header.contains("交易号") && header.contains("商家订单号") {
            return .alipay
        }
        if header.contains("招商银行") || header.contains("cmb") {
            return .bankCMB
        }
        if header.contains("工商银行") || header.contains("icbc") {
            return .bankICBC
        }
        if header.contains("建设银行") || header.contains("ccb") {
            return .bankCCB
        }
        // 检查是否是短信格式
        if content.contains("余额") && (content.contains("支出") || content.contains("消费") || content.contains("转入")) {
            return .smsClipboard
        }

        return .unknown
    }

    // MARK: - 微信账单解析
    // 微信 CSV 格式：
    // 前16行是头部信息，跳过
    // 交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
    static func parseWechatCSV(content: String) -> CSVParseResult {
        var transactions: [Transaction] = []
        var errors: [String] = []
        var skipped = 0

        let lines = content.components(separatedBy: .newlines)

        // 找到数据起始行（跳过微信的头部信息）
        var dataStartIndex = 0
        for (index, line) in lines.enumerated() {
            if line.contains("交易时间") && line.contains("交易对方") {
                dataStartIndex = index + 1
                break
            }
        }
        if dataStartIndex == 0 { dataStartIndex = 17 } // 默认跳过16行头部

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        for i in dataStartIndex..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 8 else {
                skipped += 1
                continue
            }

            // 交易时间, 交易类型, 交易对方, 商品, 收/支, 金额(元), 支付方式, 当前状态
            let dateStr = fields[0].trimmingCharacters(in: .whitespaces)
            let tradeType = fields[1].trimmingCharacters(in: .whitespaces)
            let counterpart = fields[2].trimmingCharacters(in: .whitespaces)
            let goods = fields[3].trimmingCharacters(in: .whitespaces)
            let direction = fields[4].trimmingCharacters(in: .whitespaces)
            let amountStr = fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "¥ "))
            let payMethod = fields[6].trimmingCharacters(in: .whitespaces)
            let status = fields[7].trimmingCharacters(in: .whitespaces)

            // 跳过已退款/已关闭
            if status.contains("退款") || status.contains("关闭") {
                skipped += 1
                continue
            }

            guard let amount = Double(amountStr), let date = dateFormatter.date(from: dateStr) else {
                errors.append("第\(i+1)行解析失败: \(line.prefix(50))")
                skipped += 1
                continue
            }

            let type: TransactionType = direction.contains("收入") ? .income : .expense
            let category = guessCategory(note: goods, merchant: counterpart, tradeType: tradeType)

            transactions.append(Transaction(
                type: type,
                amount: amount,
                category: category,
                channel: .wechat,
                note: goods,
                date: date,
                merchant: counterpart
            ))
        }

        let dateRange = formatDateRange(transactions.map { $0.date })
        return CSVParseResult(source: .wechat, transactions: transactions,
                              skippedRows: skipped, errors: errors, dateRange: dateRange)
    }

    // MARK: - 支付宝账单解析
    // 支付宝 CSV 格式：
    // 前4行头部
    // 交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注
    static func parseAlipayCSV(content: String) -> CSVParseResult {
        var transactions: [Transaction] = []
        var errors: [String] = []
        var skipped = 0

        let lines = content.components(separatedBy: .newlines)

        var dataStartIndex = 0
        for (index, line) in lines.enumerated() {
            if line.contains("交易号") && line.contains("商家订单号") {
                dataStartIndex = index + 1
                break
            }
        }
        if dataStartIndex == 0 { dataStartIndex = 5 }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        // 支付宝末尾有汇总行，需要检测
        let endMarker = "---"

        for i in dataStartIndex..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(endMarker) || line.hasPrefix("已上述") { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 12 else {
                skipped += 1
                continue
            }

            // 交易创建时间(2), 交易对方(7), 商品名称(8), 金额(9), 收/支(10), 交易状态(11)
            let dateStr = fields[2].trimmingCharacters(in: .whitespaces)
            let counterpart = fields[7].trimmingCharacters(in: .whitespaces)
            let goods = fields[8].trimmingCharacters(in: .whitespaces)
            let amountStr = fields[9].trimmingCharacters(in: CharacterSet(charactersIn: "¥ "))
            let direction = fields[10].trimmingCharacters(in: .whitespaces)
            let status = fields[11].trimmingCharacters(in: .whitespaces)

            if status.contains("退款") || status.contains("关闭") {
                skipped += 1
                continue
            }

            guard let amount = Double(amountStr), let date = dateFormatter.date(from: dateStr) else {
                errors.append("第\(i+1)行解析失败")
                skipped += 1
                continue
            }

            let type: TransactionType = direction.contains("收入") ? .income : .expense
            let category = guessCategory(note: goods, merchant: counterpart, tradeType: "")

            transactions.append(Transaction(
                type: type,
                amount: amount,
                category: category,
                channel: .alipay,
                note: goods,
                date: date,
                merchant: counterpart
            ))
        }

        let dateRange = formatDateRange(transactions.map { $0.date })
        return CSVParseResult(source: .alipay, transactions: transactions,
                              skippedRows: skipped, errors: errors, dateRange: dateRange)
    }

    // MARK: - 招商银行账单解析
    static func parseCMBCSV(content: String) -> CSVParseResult {
        var transactions: [Transaction] = []
        var errors: [String] = []
        var skipped = 0

        let lines = content.components(separatedBy: .newlines)

        var dataStartIndex = 0
        for (index, line) in lines.enumerated() {
            if line.contains("交易日期") || line.contains("记账日期") {
                dataStartIndex = index + 1
                break
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"

        for i in dataStartIndex..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 5 else {
                skipped += 1
                continue
            }

            // 交易日期, 交易摘要, 交易金额, 余额, 交易对方
            let dateStr = fields[0].trimmingCharacters(in: .whitespaces)
            let summary = fields[1].trimmingCharacters(in: .whitespaces)
            let amountStr = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "¥ ,"))
            let counterpart = fields.count > 4 ? fields[4].trimmingCharacters(in: .whitespaces) : ""

            guard let amount = Double(amountStr), let date = dateFormatter.date(from: dateStr) else {
                errors.append("第\(i+1)行解析失败")
                skipped += 1
                continue
            }

            let type: TransactionType = amount > 0 ? .income : .expense
            let category = guessCategory(note: summary, merchant: counterpart, tradeType: "")

            transactions.append(Transaction(
                type: type,
                amount: abs(amount),
                category: category,
                channel: .bankCard,
                note: summary,
                date: date,
                merchant: counterpart
            ))
        }

        let dateRange = formatDateRange(transactions.map { $0.date })
        return CSVParseResult(source: .bankCMB, transactions: transactions,
                              skippedRows: skipped, errors: errors, dateRange: dateRange)
    }

    // MARK: - 通用 CSV 解析（智能列匹配）
    static func parseGenericCSV(content: String) -> CSVParseResult {
        var transactions: [Transaction] = []
        var errors: [String] = []
        var skipped = 0

        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else {
            return CSVParseResult(source: .unknown, transactions: [], skippedRows: 0, errors: ["文件为空"], dateRange: "")
        }

        // 解析头部，识别列
        let header = parseCSVLine(lines[0]).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        let dateCol = header.firstIndex(where: { $0.contains("日期") || $0.contains("时间") || $0.contains("date") })
        let amountCol = header.firstIndex(where: { $0.contains("金额") || $0.contains("amount") || $0.contains("钱") })
        let noteCol = header.firstIndex(where: { $0.contains("摘要") || $0.contains("备注") || $0.contains("说明") || $0.contains("描述") || $0.contains("商品") })
        let merchantCol = header.firstIndex(where: { $0.contains("对方") || $0.contains("商户") || $0.contains("商家") || $0.contains("merchant") })
        let dirCol = header.firstIndex(where: { $0.contains("收/支") || $0.contains("收支") || $0.contains("类型") || $0.contains("direction") })

        guard let dc = dateCol, let ac = amountCol else {
            return CSVParseResult(source: .unknown, transactions: [], skippedRows: lines.count - 1,
                                  errors: ["无法识别日期/金额列，请检查CSV格式"], dateRange: "")
        }

        let dateParsers = buildDateParsers()

        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard fields.count > max(dc, ac) else { skipped += 1; continue }

            let dateStr = fields[dc].trimmingCharacters(in: .whitespaces)
            let amountStr = fields[ac].trimmingCharacters(in: CharacterSet(charactersIn: "¥$, "))

            guard let amount = Double(amountStr) else { skipped += 1; continue }
            guard let date = tryParseDate(dateStr, parsers: dateParsers) else { skipped += 1; continue }

            let note = noteCol != nil && fields.count > noteCol! ? fields[noteCol!].trimmingCharacters(in: .whitespaces) : ""
            let merchant = merchantCol != nil && fields.count > merchantCol! ? fields[merchantCol!].trimmingCharacters(in: .whitespaces) : ""
            let dirStr = dirCol != nil && fields.count > dirCol! ? fields[dirCol!].trimmingCharacters(in: .whitespaces) : ""

            let type: TransactionType
            if !dirStr.isEmpty {
                type = dirStr.contains("收入") || dirStr.contains("入") ? .income : .expense
            } else {
                type = amount >= 0 ? .income : .expense
            }

            let category = guessCategory(note: note, merchant: merchant, tradeType: "")

            transactions.append(Transaction(
                type: type,
                amount: abs(amount),
                category: category,
                channel: .bankCard,
                note: note,
                date: date,
                merchant: merchant
            ))
        }

        let dateRange = formatDateRange(transactions.map { $0.date })
        return CSVParseResult(source: .bankGeneric, transactions: transactions,
                              skippedRows: skipped, errors: errors, dateRange: dateRange)
    }

    // MARK: - 短信文本解析
    static func parseSMSText(content: String) -> CSVParseResult {
        var transactions: [Transaction] = []
        var errors: [String] = []

        // 支持多条短信（按换行分割）
        let messages = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let amountPatterns = [
            try? NSRegularExpression(pattern: "(?:支出|消费|扣款|付款|转出)[^\\d]*(\\d+[,.]?\\d*\\.?\\d+)"),
            try? NSRegularExpression(pattern: "(?:收入|转入|到账|入账)[^\\d]*(\\d+[,.]?\\d*\\.?\\d+)"),
            try? NSRegularExpression(pattern: "(?:人民币|RMB|CNY)[^\\d]*(\\d+[,.]?\\d*\\.?\\d+)"),
            try? NSRegularExpression(pattern: "金额[^\\d]*(\\d+[,.]?\\d*\\.?\\d+)"),
        ]

        let datePattern = try? NSRegularExpression(pattern: "(\\d{1,2}月\\d{1,2}日|\\d{4}[-/]\\d{1,2}[-/]\\d{1,2})")
        let merchantPattern = try? NSRegularExpression(pattern: "(?:在|向|于)([\\u4e00-\\u9fa5A-Za-z0-9*]+?)(?:消费|支出|扣款|付款|转出|收入)")

        for msg in messages {
            let range = NSRange(msg.startIndex..., in: msg)

            // 提取金额
            var amount: Double?
            var isIncome = false

            for (index, pattern) in amountPatterns.compactMap({ $0 }).enumerated() {
                if let match = pattern.firstMatch(in: msg, range: range),
                   let amtRange = Range(match.range(at: 1), in: msg) {
                    let amtStr = String(msg[amtRange]).replacingOccurrences(of: ",", with: "")
                    amount = Double(amtStr)
                    isIncome = (index == 1) // 第二个模式是收入
                    break
                }
            }

            guard let amt = amount else { continue }

            // 提取日期
            var date = Date()
            if let dateMatch = datePattern?.firstMatch(in: msg, range: range),
               let dateRange = Range(dateMatch.range(at: 1), in: msg) {
                let dateStr = String(msg[dateRange])
                if let parsed = parseSMSDate(dateStr) {
                    date = parsed
                }
            }

            // 提取商家
            var merchant = ""
            if let merchantMatch = merchantPattern?.firstMatch(in: msg, range: range),
               let mRange = Range(merchantMatch.range(at: 1), in: msg) {
                merchant = String(msg[mRange])
            }

            // 判断银行
            let channel: PaymentChannel = .bankCard

            transactions.append(Transaction(
                type: isIncome ? .income : .expense,
                amount: amt,
                category: guessCategory(note: msg, merchant: merchant, tradeType: ""),
                channel: channel,
                note: String(msg.prefix(50)),
                date: date,
                merchant: merchant
            ))
        }

        let dateRange = formatDateRange(transactions.map { $0.date })
        return CSVParseResult(source: .smsClipboard, transactions: transactions,
                              skippedRows: 0, errors: errors, dateRange: dateRange)
    }

    // MARK: - 智能分类推断
    static func guessCategory(note: String, merchant: String, tradeType: String) -> ExpenseCategory {
        let text = (note + merchant + tradeType).lowercased()

        // 餐饮关键词
        let foodKeywords = ["餐", "食", "饭", "面", "粥", "咖啡", "奶茶", "饮", "外卖", "美团", "饿了么",
                           "肯德基", "麦当劳", "星巴克", "瑞幸", "海底捞", "火锅", "烧烤", "小吃",
                           "便利店", "超市", "fruit", "food", "菜", "早餐", "午餐", "晚餐", "夜宵",
                           "盒马", "叮咚", "每日优鲜", "拼多多买菜", "soda", "tea", "coffee"]
        if foodKeywords.contains(where: { text.contains($0) }) { return .food }

        // 交通关键词
        let transportKeywords = ["地铁", "公交", "出租", "打车", "滴滴", "高德", "uber", "曹操",
                                "加油", "停车", "高速", "过路费", "火车", "机票", "航空", "12306",
                                "铁路", "汽车票", "单车", "哈啰", "青桔"]
        if transportKeywords.contains(where: { text.contains($0) }) { return .transport }

        // 购物关键词
        let shoppingKeywords = ["淘宝", "天猫", "京东", "拼多多", "唯品会", "amazon", "苏宁",
                               "购物", "商城", "优衣库", "zara", "nike", "adidas", "数码",
                               "电器", "家电", "手机", "电脑"]
        if shoppingKeywords.contains(where: { text.contains($0) }) { return .shopping }

        // 娱乐关键词
        let entertainmentKeywords = ["电影", "影城", "ktv", "游戏", "网易", "腾讯游戏", "steam",
                                    "演出", "门票", "旅游", "酒店", "民宿", "airbnb"]
        if entertainmentKeywords.contains(where: { text.contains($0) }) { return .entertainment }

        // 住房关键词
        let housingKeywords = ["房租", "租金", "物业", "房贷", "mortgage", "公寓"]
        if housingKeywords.contains(where: { text.contains($0) }) { return .housing }

        // 医疗关键词
        let medicalKeywords = ["医院", "药", "挂号", "门诊", "体检", "口腔", "牙", "眼科", "pharmacy"]
        if medicalKeywords.contains(where: { text.contains($0) }) { return .medical }

        // 教育关键词
        let educationKeywords = ["书", "课程", "培训", "学费", "教育", "网课", "得到", "喜马拉雅", "知乎"]
        if educationKeywords.contains(where: { text.contains($0) }) { return .education }

        // 转账关键词
        let transferKeywords = ["转账", "红包", "还款", "借", "贷", "信用卡还款"]
        if transferKeywords.contains(where: { text.contains($0) }) { return .transfer }

        // 生活缴费
        let utilityKeywords = ["电费", "水费", "燃气", "煤气", "话费", "宽带", "网费", "充值", "缴费", "电网", "自来水"]
        if utilityKeywords.contains(where: { text.contains($0) }) { return .utilities }

        return .other
    }

    // MARK: - CSV 行解析（处理引号和逗号）
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: - 日期解析工具
    private static func buildDateParsers() -> [DateFormatter] {
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd",
            "yyyyMMdd", "MM/dd/yyyy",
            "dd/MM/yyyy", "yyyy.MM.dd",
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "zh_CN")
            return df
        }
    }

    private static func tryParseDate(_ str: String, parsers: [DateFormatter]) -> Date? {
        let cleaned = str.trimmingCharacters(in: .whitespaces)
        for parser in parsers {
            if let date = parser.date(from: cleaned) { return date }
        }
        return nil
    }

    private static func parseSMSDate(_ str: String) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        if str.contains("月") && str.contains("日") {
            let parts = str.replacingOccurrences(of: "日", with: "").components(separatedBy: "月")
            if parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) {
                return calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
        }

        let parsers = buildDateParsers()
        return tryParseDate(str, parsers: parsers)
    }

    private static func formatDateRange(_ dates: [Date]) -> String {
        guard let min = dates.min(), let max = dates.max() else { return "无数据" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return "\(formatter.string(from: min)) ~ \(formatter.string(from: max))"
    }
}
