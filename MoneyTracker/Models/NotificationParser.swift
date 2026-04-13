import Foundation

// MARK: - 微信/支付宝支付通知解析引擎
// 捕获系统推送通知的文本内容，解析出金额、商户、支付渠道
// 配合 iOS 快捷指令的「通知触发」自动化，实现零操作记账

class NotificationParser {
    
    // MARK: - 解析结果
    struct ParseResult {
        let amount: Double
        let merchant: String
        let channel: PaymentChannel
        let category: ExpenseCategory
        let type: TransactionType
        let confidence: Double // 0~1 置信度
        let rawText: String
        
        var isValid: Bool { amount > 0 && confidence > 0.5 }
    }
    
    // MARK: - 主入口：自动识别并解析通知文本
    static func parse(notificationText: String, source: String = "") -> ParseResult? {
        let text = notificationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        
        // 尝试各渠道解析器
        if let result = parseWechatNotification(text) { return result }
        if let result = parseAlipayNotification(text) { return result }
        if let result = parseBankSMSNotification(text) { return result }
        
        // 通用金额提取（兜底）
        return parseGenericNotification(text, source: source)
    }
    
    // MARK: - 微信支付通知解析
    // 微信通知格式示例：
    //   "微信支付成功 ¥35.50 沙县小吃"
    //   "微信支付 收款到账¥200.00"
    //   "向沙县小吃付款35.50元"
    //   "你已成功向商户(沙县小吃)付款人民币35.50元"
    //   "微信支付凭证：消费 35.50元 沙县小吃"
    private static func parseWechatNotification(_ text: String) -> ParseResult? {
        // 判断是否为微信通知
        let wechatKeywords = ["微信支付", "微信红包", "微信转账", "零钱", "向商户", "付款成功"]
        guard wechatKeywords.contains(where: { text.contains($0) }) else { return nil }
        
        var amount: Double = 0
        var merchant = ""
        var type: TransactionType = .expense
        var confidence: Double = 0.8
        
        // 识别收入场景
        let incomeKeywords = ["收款到账", "已收到", "转账收款", "红包", "退款"]
        if incomeKeywords.contains(where: { text.contains($0) }) {
            type = .income
        }
        
        // 提取金额 - 多种格式
        let amountPatterns = [
            "¥([\\d,]+\\.?\\d*)",                          // ¥35.50
            "￥([\\d,]+\\.?\\d*)",                          // ￥35.50
            "付款[人民币]*([\\d,]+\\.?\\d*)元",              // 付款35.50元
            "消费\\s*([\\d,]+\\.?\\d*)\\s*元",              // 消费 35.50 元
            "金额[：:]?\\s*([\\d,]+\\.?\\d*)",              // 金额：35.50
            "([\\d,]+\\.?\\d*)\\s*元",                      // 35.50元
            "到账([\\d,]+\\.?\\d*)",                        // 到账200.00
        ]
        
        for pattern in amountPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[match])
                if let extracted = extractNumber(from: matched) {
                    amount = extracted
                    confidence = 0.9
                    break
                }
            }
        }
        
        // 提取商户
        let merchantPatterns = [
            "向(.+?)付款",                    // 向沙县小吃付款
            "商户[\\(（](.+?)[\\)）]",          // 商户(沙县小吃)
            "在(.+?)消费",                     // 在沙县小吃消费
            "付给(.+?)\\s",                    // 付给沙县小吃
            "¥[\\d,.]+\\s+(.+?)$",            // ¥35.50 沙县小吃
            "￥[\\d,.]+\\s+(.+?)$",            // ￥35.50 沙县小吃
            "消费[\\d,.]+元\\s*(.+?)$",        // 消费35.50元 沙县小吃
        ]
        
        for pattern in merchantPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                let cleaned = matched
                    .replacingOccurrences(of: "向|付款|商户|在|消费|付给|[¥￥\\d,.元\\(\\)（）\\s]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count <= 20 {
                    merchant = cleaned
                    break
                }
            }
        }
        
        guard amount > 0 else { return nil }
        
        return ParseResult(
            amount: amount,
            merchant: merchant,
            channel: .wechat,
            category: categorize(merchant: merchant, amount: amount),
            type: type,
            confidence: confidence,
            rawText: text
        )
    }
    
    // MARK: - 支付宝通知解析
    // 支付宝通知格式示例：
    //   "支付宝付款 35.50元 美团外卖"
    //   "你在美团外卖消费35.50元，支付宝已扣款"
    //   "支付宝到账200元"
    //   "花呗还款成功，金额500.00元"
    //   "余额宝收益到账0.85元"
    private static func parseAlipayNotification(_ text: String) -> ParseResult? {
        let alipayKeywords = ["支付宝", "花呗", "余额宝", "蚂蚁", "芝麻", "口碑"]
        guard alipayKeywords.contains(where: { text.contains($0) }) else { return nil }
        
        var amount: Double = 0
        var merchant = ""
        var type: TransactionType = .expense
        var confidence: Double = 0.8
        
        // 收入识别
        let incomeKeywords = ["到账", "收款", "退款", "收益", "返现", "红包"]
        if incomeKeywords.contains(where: { text.contains($0) }) {
            type = .income
        }
        
        // 提取金额
        let amountPatterns = [
            "¥([\\d,]+\\.?\\d*)",
            "￥([\\d,]+\\.?\\d*)",
            "([\\d,]+\\.?\\d*)\\s*元",
            "金额[：:]?\\s*([\\d,]+\\.?\\d*)",
            "扣款([\\d,]+\\.?\\d*)",
            "消费([\\d,]+\\.?\\d*)",
        ]
        
        for pattern in amountPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[match])
                if let extracted = extractNumber(from: matched) {
                    amount = extracted
                    confidence = 0.9
                    break
                }
            }
        }
        
        // 提取商户
        let merchantPatterns = [
            "你在(.+?)消费",
            "向(.+?)付款",
            "付款[\\s¥￥\\d.元]*(.+?)$",
            "在(.+?)支付",
            "商户[：:]?\\s*(.+?)\\s",
        ]
        
        for pattern in merchantPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                let cleaned = matched
                    .replacingOccurrences(of: "你在|消费|向|付款|在|支付|商户|[：:\\s¥￥\\d.元]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count <= 20 {
                    merchant = cleaned
                    break
                }
            }
        }
        
        guard amount > 0 else { return nil }
        
        return ParseResult(
            amount: amount,
            merchant: merchant,
            channel: .alipay,
            category: categorize(merchant: merchant, amount: amount),
            type: type,
            confidence: confidence,
            rawText: text
        )
    }
    
    // MARK: - 银行短信/通知解析（补充）
    private static func parseBankSMSNotification(_ text: String) -> ParseResult? {
        let bankKeywords = ["银行", "信用卡", "储蓄卡", "借记卡", "尾号", "账户"]
        guard bankKeywords.contains(where: { text.contains($0) }) else { return nil }
        
        var amount: Double = 0
        var merchant = ""
        var type: TransactionType = .expense
        
        // 收支判断
        if text.contains("支出") || text.contains("消费") || text.contains("扣款") || text.contains("转出") {
            type = .expense
        } else if text.contains("收入") || text.contains("入账") || text.contains("转入") || text.contains("到账") {
            type = .income
        }
        
        // 金额提取
        let amountPatterns = [
            "人民币([\\d,]+\\.?\\d*)",
            "RMB([\\d,]+\\.?\\d*)",
            "([\\d,]+\\.?\\d*)\\s*元",
        ]
        
        for pattern in amountPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                if let extracted = extractNumber(from: String(text[match])) {
                    amount = extracted
                    break
                }
            }
        }
        
        // 商户提取
        if let range = text.range(of: "(?:在|商户|摘要)[：:]?\\s*(.+?)(?:\\s|，|,|。|$)", options: .regularExpression) {
            let cleaned = String(text[range])
                .replacingOccurrences(of: "在|商户|摘要|[：:]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count <= 20 { merchant = cleaned }
        }
        
        guard amount > 0 else { return nil }
        
        return ParseResult(
            amount: amount,
            merchant: merchant,
            channel: .bankCard,
            category: categorize(merchant: merchant, amount: amount),
            type: type,
            confidence: 0.75,
            rawText: text
        )
    }
    
    // MARK: - 通用解析（兜底）
    private static func parseGenericNotification(_ text: String, source: String) -> ParseResult? {
        // 尝试从任何文本中提取金额
        guard let amount = extractNumber(from: text), amount > 0 && amount < 1000000 else {
            return nil
        }
        
        // 通过 source 判断渠道
        let channel: PaymentChannel
        let lowSource = source.lowercased()
        if lowSource.contains("微信") || lowSource.contains("wechat") || lowSource.contains("weixin") {
            channel = .wechat
        } else if lowSource.contains("支付宝") || lowSource.contains("alipay") {
            channel = .alipay
        } else {
            channel = .other
        }
        
        return ParseResult(
            amount: amount,
            merchant: "",
            channel: channel,
            category: categorize(merchant: "", amount: amount),
            type: .expense,
            confidence: 0.5,
            rawText: text
        )
    }
    
    // MARK: - 智能分类引擎
    static func categorize(merchant: String, amount: Double) -> ExpenseCategory {
        let m = merchant.lowercased()
        
        // 餐饮
        let foodKeywords = ["餐", "饭", "食", "吃", "外卖", "美团", "饿了么", "肯德基", "麦当劳", "星巴克",
                            "瑞幸", "沙县", "兰州", "海底捞", "西贝", "必胜客", "喜茶", "奶茶", "咖啡",
                            "烧烤", "火锅", "面馆", "便当", "早餐", "午餐", "晚餐", "小吃", "蛋糕",
                            "面包", "烘焙", "水果", "超市", "便利", "菜市场"]
        if foodKeywords.contains(where: { m.contains($0) }) { return .food }
        
        // 交通
        let transportKeywords = ["滴滴", "出行", "打车", "地铁", "公交", "高铁", "火车", "飞机", "航空",
                                 "加油", "停车", "高速", "过路", "出租", "曹操", "首汽", "12306",
                                 "摩拜", "哈啰", "共享", "单车"]
        if transportKeywords.contains(where: { m.contains($0) }) { return .transport }
        
        // 购物
        let shoppingKeywords = ["京东", "淘宝", "天猫", "拼多多", "苏宁", "国美", "优衣库", "zara",
                                "h&m", "商城", "百货", "购物", "旗舰店", "专卖", "服装", "鞋",
                                "数码", "电器", "家居", "唯品", "当当", "亚马逊"]
        if shoppingKeywords.contains(where: { m.contains($0) }) { return .shopping }
        
        // 娱乐
        let entertainKeywords = ["电影", "影城", "万达", "影院", "ktv", "游戏", "网易", "腾讯",
                                 "bilibili", "爱奇艺", "优酷", "抖音", "直播", "演出", "门票",
                                 "旅游", "景区", "酒店", "民宿", "携程", "去哪儿", "飞猪"]
        if entertainKeywords.contains(where: { m.contains($0) }) { return .entertainment }
        
        // 住房
        let housingKeywords = ["房租", "房东", "物业", "水电", "燃气", "暖气", "装修", "家具",
                               "自如", "贝壳", "链家"]
        if housingKeywords.contains(where: { m.contains($0) }) { return .housing }
        
        // 医疗
        let medicalKeywords = ["医院", "诊所", "药", "挂号", "体检", "口腔", "眼科", "丁香"]
        if medicalKeywords.contains(where: { m.contains($0) }) { return .medical }
        
        // 教育
        let eduKeywords = ["教育", "培训", "课程", "学费", "考试", "书", "图书", "知乎",
                           "得到", "读书", "学习", "网课"]
        if eduKeywords.contains(where: { m.contains($0) }) { return .education }
        
        // 生活缴费
        let utilKeywords = ["电费", "水费", "话费", "宽带", "充值", "缴费", "国家电网",
                            "移动", "联通", "电信"]
        if utilKeywords.contains(where: { m.contains($0) }) { return .utilities }
        
        // 转账
        let transferKeywords = ["转账", "还款", "借款", "红包"]
        if transferKeywords.contains(where: { m.contains($0) }) { return .transfer }
        
        // 按金额大致推断
        if amount < 30 { return .food }
        if amount < 100 { return .shopping }
        
        return .other
    }
    
    // MARK: - 数字提取工具
    private static func extractNumber(from text: String) -> Double? {
        let pattern = "([\\d,]+\\.\\d+|[\\d,]+)"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
    }
}

// MARK: - 通知记录日志
struct NotificationRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let source: String       // "微信" / "支付宝" / "银行"
    let rawText: String
    let parsedAmount: Double?
    let parsedMerchant: String?
    let success: Bool
    
    init(source: String, rawText: String, result: NotificationParser.ParseResult?) {
        self.id = UUID()
        self.date = Date()
        self.source = source
        self.rawText = rawText
        self.parsedAmount = result?.amount
        self.parsedMerchant = result?.merchant
        self.success = result?.isValid ?? false
    }
}
