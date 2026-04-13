import Foundation

// MARK: - 交易类型
enum TransactionType: String, Codable, CaseIterable {
    case expense = "支出"
    case income = "收入"
}

// MARK: - 支付渠道
enum PaymentChannel: String, Codable, CaseIterable, Identifiable {
    case wechat = "微信支付"
    case alipay = "支付宝"
    case bankCard = "银行卡"
    case cash = "现金"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wechat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .bankCard: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .wechat: return "wechatGreen"
        case .alipay: return "alipayBlue"
        case .bankCard: return "bankOrange"
        case .cash: return "cashYellow"
        case .other: return "gray"
        }
    }
}

// MARK: - 支出分类
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food = "餐饮"
    case transport = "交通"
    case shopping = "购物"
    case entertainment = "娱乐"
    case housing = "住房"
    case medical = "医疗"
    case education = "教育"
    case transfer = "转账"
    case utilities = "生活缴费"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "gamecontroller.fill"
        case .housing: return "house.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .utilities: return "bolt.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .food: return "orange"
        case .transport: return "blue"
        case .shopping: return "pink"
        case .entertainment: return "purple"
        case .housing: return "brown"
        case .medical: return "red"
        case .education: return "teal"
        case .transfer: return "indigo"
        case .utilities: return "yellow"
        case .other: return "gray"
        }
    }
}

// MARK: - 交易记录
struct Transaction: Identifiable, Codable {
    let id: UUID
    var type: TransactionType
    var amount: Double
    var category: ExpenseCategory
    var channel: PaymentChannel
    var note: String
    var date: Date
    var merchant: String

    init(
        id: UUID = UUID(),
        type: TransactionType = .expense,
        amount: Double,
        category: ExpenseCategory,
        channel: PaymentChannel,
        note: String = "",
        date: Date = Date(),
        merchant: String = ""
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.category = category
        self.channel = channel
        self.note = note
        self.date = date
        self.merchant = merchant
    }
}

// MARK: - 月度统计
struct MonthlyStatistics {
    var totalExpense: Double
    var totalIncome: Double
    var categoryBreakdown: [(category: ExpenseCategory, amount: Double, percentage: Double)]
    var channelBreakdown: [(channel: PaymentChannel, amount: Double, percentage: Double)]
    var dailyExpenses: [(date: Date, amount: Double)]

    var balance: Double { totalIncome - totalExpense }
}
