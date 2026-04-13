import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedChannel: PaymentChannel = .wechat
    @State private var note = ""
    @State private var merchant = ""
    @State private var date = Date()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 收支类型切换
                    typeToggle

                    // 金额输入
                    amountInput

                    // 分类选择
                    categoryPicker

                    // 支付渠道
                    channelPicker

                    // 备注信息
                    detailInputs
                }
                .padding(16)
            }
            .background(Color(hex: "F5F5F7"))
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { saveTransaction() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "4F46E5"))
                        .disabled(amountText.isEmpty)
                }
            }
        }
    }

    // MARK: - 收支切换
    private var typeToggle: some View {
        HStack(spacing: 0) {
            ForEach([TransactionType.expense, .income], id: \.self) { t in
                Button(action: { withAnimation(.spring(response: 0.3)) { type = t } }) {
                    Text(t.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(type == t ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            type == t ?
                            AnyView(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(type == .expense ? Color(hex: "EF4444") : Color(hex: "10B981"))
                            ) : AnyView(Color.clear)
                        )
                }
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - 金额输入
    private var amountInput: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField("0.00", text: $amountText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
    }

    // MARK: - 分类选择
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类")
                .font(.system(size: 15, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(ExpenseCategory.allCases) { cat in
                    Button(action: { selectedCategory = cat }) {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selectedCategory == cat ?
                                          categoryColor(cat) :
                                          categoryColor(cat).opacity(0.1))
                                    .frame(width: 48, height: 48)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedCategory == cat ? .white : categoryColor(cat))
                            }
                            Text(cat.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(selectedCategory == cat ? categoryColor(cat) : .secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
    }

    // MARK: - 渠道选择
    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支付方式")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                ForEach(PaymentChannel.allCases) { ch in
                    Button(action: { selectedChannel = ch }) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(selectedChannel == ch ?
                                          channelDisplayColor(ch) :
                                          channelDisplayColor(ch).opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: ch.icon)
                                    .font(.system(size: 17))
                                    .foregroundColor(selectedChannel == ch ? .white : channelDisplayColor(ch))
                            }
                            Text(channelShortName(ch))
                                .font(.system(size: 10))
                                .foregroundColor(selectedChannel == ch ? channelDisplayColor(ch) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
    }

    // MARK: - 详细信息
    private var detailInputs: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                TextField("商家名称（可选）", text: $merchant)
                    .font(.system(size: 15))
            }

            Divider()

            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                TextField("备注说明（可选）", text: $note)
                    .font(.system(size: 15))
            }

            Divider()

            DatePicker(selection: $date, displayedComponents: [.date, .hourAndMinute]) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                    Text("日期")
                        .font(.system(size: 15))
                }
            }
        }
        .padding(16)
        .background(.white)
        .cornerRadius(16)
    }

    // MARK: - Helpers
    private func saveTransaction() {
        guard let amount = Double(amountText), amount > 0 else { return }
        let transaction = Transaction(
            type: type,
            amount: amount,
            category: selectedCategory,
            channel: selectedChannel,
            note: note,
            date: date,
            merchant: merchant
        )
        viewModel.addTransaction(transaction)
        dismiss()
    }

    private func categoryColor(_ cat: ExpenseCategory) -> Color {
        switch cat {
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
