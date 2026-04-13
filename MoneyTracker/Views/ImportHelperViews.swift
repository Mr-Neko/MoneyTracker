import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文档选择器
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [UTType.commaSeparatedText, UTType.plainText, UTType.data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - 短信粘贴输入
struct SMSInputView: View {
    let onImport: (CSVParseResult) -> Void
    @State private var inputText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("粘贴银行短信/账单文本")
                .font(.headline)

            TextEditor(text: $inputText)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            if !inputText.isEmpty {
                Text("识别到 \(inputText.count) 个字符")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                let result = CSVParser.autoParseCSV(content: inputText)
                onImport(result)
            }) {
                Text("解析并导入")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(inputText.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(12)
            }
            .disabled(inputText.isEmpty)

            Spacer()
        }
        .padding(20)
        .navigationTitle("粘贴短信")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("取消") { dismiss() }
            }
        }
    }
}

// MARK: - 导入结果展示
struct ImportResultView: View {
    let result: CSVParseResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            if let result = result {
                Image(systemName: result.successCount > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(result.successCount > 0 ? .green : .orange)

                Text(result.successCount > 0 ? "导入成功" : "未识别到记录")
                    .font(.system(size: 22, weight: .bold))

                VStack(spacing: 8) {
                    resultRow(label: "来源", value: result.source.rawValue)
                    resultRow(label: "成功导入", value: "\(result.successCount) 条")
                    resultRow(label: "跳过", value: "\(result.skippedRows) 条")
                    resultRow(label: "时间范围", value: result.dateRange)
                }
                .padding(20)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(16)

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("错误信息")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                        ForEach(result.errors.prefix(5), id: \.self) { error in
                            Text("• \(error)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
            } else {
                Text("无导入结果")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("完成") { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .cornerRadius(12)
                .padding(.bottom, 16)
        }
        .padding(24)
        .navigationTitle("导入结果")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

// MARK: - 邮箱配置页
struct EmailConfigView: View {
    @ObservedObject var fetcher: EmailBillFetcher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("邮箱账户") {
                TextField("邮箱地址", text: $fetcher.config.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                SecureField("授权码（非登录密码）", text: $fetcher.config.password)
            }

            Section("IMAP 服务器") {
                Picker("预设", selection: Binding(
                    get: { fetcher.config.imapServer },
                    set: { server in
                        if let preset = EmailConfig.presets.first(where: { $0.server == server }) {
                            fetcher.config.applyPreset(preset)
                        }
                    }
                )) {
                    Text("选择邮箱类型").tag("")
                    ForEach(EmailConfig.presets, id: \.server) { preset in
                        Text(preset.name).tag(preset.server)
                    }
                }
                TextField("IMAP 服务器", text: $fetcher.config.imapServer)
                TextField("端口", value: $fetcher.config.imapPort, format: .number)
                Toggle("使用 SSL", isOn: $fetcher.config.useSSL)
            }

            Section {
                Toggle("定时自动拉取", isOn: $fetcher.config.autoFetchEnabled)
                if fetcher.config.autoFetchEnabled {
                    Stepper("间隔 \(fetcher.config.autoFetchIntervalHours) 小时",
                            value: $fetcher.config.autoFetchIntervalHours, in: 1...72)
                }
            }

            Section {
                Button(action: {
                    fetcher.saveConfig()
                    fetcher.fetchBills { _ in }
                }) {
                    HStack {
                        Spacer()
                        if fetcher.fetchStatus == .fetching {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(fetcher.fetchStatus == .fetching ? "拉取中..." : "保存并立即拉取")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                }
                .disabled(!fetcher.config.isValid || fetcher.fetchStatus == .fetching)
            }

            if !fetcher.fetchLog.isEmpty {
                Section("日志") {
                    ForEach(fetcher.fetchLog.suffix(10)) { entry in
                        Text(entry.message)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("邮箱配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    fetcher.saveConfig()
                    dismiss()
                }
            }
        }
    }
}
