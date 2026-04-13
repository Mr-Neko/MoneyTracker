import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var viewModel: TransactionViewModel

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.groupedByDate, id: \.date) { group in
                        Section {
                            VStack(spacing: 0) {
                                ForEach(group.transactions) { transaction in
                                    TransactionRowView(transaction: transaction)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)

                                    if transaction.id != group.transactions.last?.id {
                                        Divider()
                                            .padding(.leading, 68)
                                    }
                                }
                            }
                            .background(.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                            .padding(.horizontal, 16)
                        } header: {
                            dateHeader(for: group.date, transactions: group.transactions)
                        }
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
            }
            .background(Color(hex: "F5F5F7"))
            .navigationTitle("交易明细")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func dateHeader(for date: Date, transactions: [Transaction]) -> some View {
        let dayExpense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let dayIncome = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }

        return HStack {
            Text(dateString(date))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            if dayExpense > 0 {
                Text("支出 ¥\(String(format: "%.0f", dayExpense))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if dayIncome > 0 {
                Text("收入 ¥\(String(format: "%.0f", dayIncome))")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "10B981"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(hex: "F5F5F7").opacity(0.95))
    }

    private func dateString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 EEEE"
            return formatter.string(from: date)
        }
    }
}
