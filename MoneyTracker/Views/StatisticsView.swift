import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var viewModel: TransactionViewModel
    @State private var selectedSegment = 0

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 月份切换
                    monthSelector

                    // 收支概览
                    summaryCards

                    // 分类/渠道 切换
                    Picker("统计维度", selection: $selectedSegment) {
                        Text("分类统计").tag(0)
                        Text("渠道统计").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if selectedSegment == 0 {
                        categoryBreakdown
                    } else {
                        channelBreakdown
                    }

                    // 每日趋势
                    dailyTrend

                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
            }
            .background(Color(hex: "F5F5F7"))
            .navigationTitle("统计分析")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - 月份选择器
    private var monthSelector: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "4F46E5"))
            }

            Spacer()

            Text(monthString)
                .font(.system(size: 17, weight: .bold))

            Spacer()

            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "4F46E5"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - 收支概览卡片
    private var summaryCards: some View {
        let stats = viewModel.monthlyStats
        return HStack(spacing: 12) {
            summaryCard(
                title: "总支出",
                amount: stats.totalExpense,
                color: Color(hex: "EF4444"),
                icon: "arrow.up.right"
            )
            summaryCard(
                title: "总收入",
                amount: stats.totalIncome,
                color: Color(hex: "10B981"),
                icon: "arrow.down.left"
            )
            summaryCard(
                title: "结余",
                amount: stats.balance,
                color: Color(hex: "4F46E5"),
                icon: "equal"
            )
        }
        .padding(.horizontal, 16)
    }

    private func summaryCard(title: String, amount: Double, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(color)

            Text("¥\(String(format: "%.0f", abs(amount)))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 分类统计
    private var categoryBreakdown: some View {
        let stats = viewModel.monthlyStats
        return VStack(alignment: .leading, spacing: 16) {
            Text("分类明细")
                .font(.system(size: 15, weight: .semibold))

            // 环形图
            if !stats.categoryBreakdown.isEmpty {
                HStack(spacing: 24) {
                    // 简化的环形图
                    ZStack {
                        ForEach(Array(stats.categoryBreakdown.enumerated()), id: \.offset) { index, item in
                            Circle()
                                .trim(from: trimStart(for: index, in: stats.categoryBreakdown),
                                      to: trimEnd(for: index, in: stats.categoryBreakdown))
                                .stroke(categoryDisplayColor(item.category), lineWidth: 20)
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(-90))
                        }

                        VStack(spacing: 2) {
                            Text("\(stats.categoryBreakdown.count)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("个分类")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 140, height: 140)

                    // 图例
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(stats.categoryBreakdown.prefix(5).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(categoryDisplayColor(item.category))
                                    .frame(width: 8, height: 8)
                                Text(item.category.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(String(format: "%.0f", item.percentage))%")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 列表
            ForEach(Array(stats.categoryBreakdown.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(categoryDisplayColor(item.category).opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: item.category.icon)
                            .font(.system(size: 15))
                            .foregroundColor(categoryDisplayColor(item.category))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.category.rawValue)
                            .font(.system(size: 14, weight: .medium))

                        // 进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(categoryDisplayColor(item.category))
                                    .frame(width: geo.size.width * item.percentage / 100, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("¥\(String(format: "%.0f", item.amount))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("\(String(format: "%.1f", item.percentage))%")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - 渠道统计
    private var channelBreakdown: some View {
        let stats = viewModel.monthlyStats
        return VStack(alignment: .leading, spacing: 16) {
            Text("渠道明细")
                .font(.system(size: 15, weight: .semibold))

            ForEach(Array(stats.channelBreakdown.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(channelDisplayColor(item.channel).opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: item.channel.icon)
                            .font(.system(size: 16))
                            .foregroundColor(channelDisplayColor(item.channel))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.channel.rawValue)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("¥\(String(format: "%.0f", item.amount))")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(channelDisplayColor(item.channel))
                                    .frame(width: geo.size.width * item.percentage / 100, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - 每日趋势
    private var dailyTrend: some View {
        let stats = viewModel.monthlyStats
        let maxAmount = stats.dailyExpenses.map { $0.amount }.max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("每日支出趋势")
                .font(.system(size: 15, weight: .semibold))

            if stats.dailyExpenses.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(stats.dailyExpenses.enumerated()), id: \.offset) { _, item in
                            VStack(spacing: 4) {
                                Text("¥\(Int(item.amount))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED")],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 24, height: max(8, CGFloat(item.amount / maxAmount) * 100))

                                Text(dayString(item.date))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 150)
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: viewModel.selectedMonth)
    }

    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: viewModel.selectedMonth) {
            viewModel.selectedMonth = newDate
        }
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func trimStart(for index: Int, in items: [(category: ExpenseCategory, amount: Double, percentage: Double)]) -> CGFloat {
        let preceding = items.prefix(index).reduce(0) { $0 + $1.percentage }
        return CGFloat(preceding / 100)
    }

    private func trimEnd(for index: Int, in items: [(category: ExpenseCategory, amount: Double, percentage: Double)]) -> CGFloat {
        let including = items.prefix(index + 1).reduce(0) { $0 + $1.percentage }
        return CGFloat(including / 100)
    }

    private func categoryDisplayColor(_ category: ExpenseCategory) -> Color {
        switch category {
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

    private func channelDisplayColor(_ channel: PaymentChannel) -> Color {
        switch channel {
        case .wechat: return Color(hex: "07C160")
        case .alipay: return Color(hex: "1677FF")
        case .bankCard: return Color(hex: "F97316")
        case .cash: return Color(hex: "EAB308")
        case .other: return .gray
        }
    }
}
