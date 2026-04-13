import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: TransactionViewModel

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 顶部概览卡片
                    overviewCard

                    // 今日支出
                    todaySection

                    // 支付渠道统计
                    channelSection

                    // 最近交易
                    recentTransactions

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(hex: "F5F5F7"))
            .navigationTitle("记账本")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - 概览卡片
    private var overviewCard: some View {
        let stats = viewModel.monthlyStats
        return VStack(spacing: 16) {
            HStack {
                Text(monthString)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(alignment: .firstTextBaseline) {
                Text("¥")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(String(format: "%.0f", stats.totalExpense))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("本月总支出")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .background(.white.opacity(0.2))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("收入")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Text("¥\(String(format: "%.0f", stats.totalIncome))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 1, height: 36)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("结余")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Text("¥\(String(format: "%.0f", stats.balance))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(stats.balance >= 0 ? .green.opacity(0.9) : .red.opacity(0.9))
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED"), Color(hex: "9333EA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: Color(hex: "4F46E5").opacity(0.3), radius: 16, y: 8)
    }

    // MARK: - 今日支出
    private var todaySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日支出")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Text("¥\(String(format: "%.1f", viewModel.todayExpense))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            Spacer()

            // 预算进度 (Demo 固定 200/天)
            let budget: Double = 200
            let progress = min(viewModel.todayExpense / budget, 1.0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("日预算 ¥\(Int(budget))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 120, height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progress > 0.8 ? Color.red : Color(hex: "4F46E5"))
                        .frame(width: 120 * progress, height: 8)
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 支付渠道统计
    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支付渠道")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                ForEach(PaymentChannel.allCases) { channel in
                    let amount = viewModel.monthlyStats.channelBreakdown
                        .first { $0.channel == channel }?.amount ?? 0

                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(channelColor(channel).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: channel.icon)
                                .font(.system(size: 18))
                                .foregroundColor(channelColor(channel))
                        }

                        Text(channelShortName(channel))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("¥\(Int(amount))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 最近交易
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近交易")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("查看全部")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "4F46E5"))
            }

            ForEach(Array(viewModel.transactions.prefix(5))) { transaction in
                TransactionRowView(transaction: transaction)
                if transaction.id != viewModel.transactions.prefix(5).last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Helpers
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: viewModel.selectedMonth)
    }

    private func channelColor(_ channel: PaymentChannel) -> Color {
        switch channel {
        case .wechat: return Color(hex: "07C160")
        case .alipay: return Color(hex: "1677FF")
        case .bankCard: return Color(hex: "F97316")
        case .cash: return Color(hex: "EAB308")
        case .other: return .gray
        }
    }

    private func channelShortName(_ channel: PaymentChannel) -> String {
        switch channel {
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        case .bankCard: return "银行卡"
        case .cash: return "现金"
        case .other: return "其他"
        }
    }
}
