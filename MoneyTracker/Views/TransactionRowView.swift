import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            // 分类图标
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(categoryColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: transaction.category.icon)
                    .font(.system(size: 17))
                    .foregroundColor(categoryColor)
            }

            // 信息
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note.isEmpty ? transaction.category.rawValue : transaction.note)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // 渠道标签
                    Text(channelShortName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(channelColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(channelColor.opacity(0.1))
                        .cornerRadius(4)

                    if !transaction.merchant.isEmpty {
                        Text(transaction.merchant)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 金额
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(transaction.type == .income ? "+" : "-")¥\(String(format: "%.1f", transaction.amount))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(transaction.type == .income ? Color(hex: "10B981") : .primary)

                Text(timeString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers
    private var categoryColor: Color {
        switch transaction.category {
        case .food: return .orange
        case .transport: return .blue
        case .shopping: return .pink
        case .entertainment: return .purple
        case .housing: return .brown
        case .medical: return .red
        case .education: return .teal
        case .transfer: return .indigo
        case .utilities: return .yellow
        case .other: return .gray
        }
    }

    private var channelColor: Color {
        switch transaction.channel {
        case .wechat: return Color(hex: "07C160")
        case .alipay: return Color(hex: "1677FF")
        case .bankCard: return Color(hex: "F97316")
        case .cash: return Color(hex: "EAB308")
        case .other: return .gray
        }
    }

    private var channelShortName: String {
        switch transaction.channel {
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        case .bankCard: return "银行卡"
        case .cash: return "现金"
        case .other: return "其他"
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: transaction.date)
    }
}
