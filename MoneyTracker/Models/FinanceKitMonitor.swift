import Foundation

// MARK: - FinanceKit 自动交易监控
// FinanceKit 仅在真机 iOS 17.4+ 上可用，模拟器不支持
// 使用 targetEnvironment(simulator) 区分编译目标

// MARK: - 辅助模型（始终可用）
struct FinanceAccount: Identifiable, Codable {
    let id: String
    let name: String
    let institution: String
    let type: String
    var isEnabled: Bool
}

struct SyncLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}

#if !targetEnvironment(simulator)
import FinanceKit

@available(iOS 17.4, *)
class FinanceKitMonitor: ObservableObject {

    @Published var isAuthorized = false
    @Published var isMonitoring = false
    @Published var accounts: [FinanceAccount] = []
    @Published var syncLog: [SyncLogEntry] = []
    @Published var lastSyncDate: Date?
    @Published var totalAutoSynced: Int = 0

    private let store = FinanceStore.shared
    private var monitorTask: Task<Void, Never>?

    private let lastSyncKey = "FinanceKit.lastSync"
    private let syncedIdsKey = "FinanceKit.syncedIds"
    private let totalSyncedKey = "FinanceKit.totalSynced"

    init() {
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        totalAutoSynced = UserDefaults.standard.integer(forKey: totalSyncedKey)
    }

    static var isAvailable: Bool {
        return FinanceStore.isDataAvailable(.financialData)
    }

    func requestAuthorization() async {
        do {
            let status = try await store.requestAuthorization()
            await MainActor.run {
                isAuthorized = (status == .authorized)
                addLog(isAuthorized ? "✅ FinanceKit 授权成功" : "❌ 用户拒绝了 FinanceKit 授权")
            }
        } catch {
            await MainActor.run {
                addLog("❌ 授权失败: \(error.localizedDescription)")
            }
        }
    }

    func loadAccounts() async {
        guard isAuthorized else { return }
        do {
            let query = AccountQuery(sortDescriptors: [], predicate: nil)
            let fetchedAccounts = try await store.accounts(query: query)
            await MainActor.run {
                accounts = fetchedAccounts.map { acct in
                    FinanceAccount(
                        id: acct.id.uuidString,
                        name: acct.displayName,
                        institution: acct.institutionName,
                        type: mapAccountType(acct),
                        isEnabled: true
                    )
                }
                addLog("📋 找到 \(accounts.count) 个金融账户")
            }
        } catch {
            await MainActor.run {
                addLog("❌ 加载账户失败: \(error.localizedDescription)")
            }
        }
    }

    func syncNewTransactions() async -> [Transaction] {
        guard isAuthorized else { return [] }
        let syncedIds = Set(UserDefaults.standard.stringArray(forKey: syncedIdsKey) ?? [])
        let since = lastSyncDate ?? Calendar.current.date(byAdding: .month, value: -6, to: Date())!

        await MainActor.run {
            addLog("🔄 开始同步 \(formatDate(since)) 以来的交易...")
        }

        do {
            let predicate = TransactionQuery.Predicate.date(after: since)
            let query = TransactionQuery(sortDescriptors: [.date(order: .reverse)], predicate: predicate)
            let rawTransactions = try await store.transactions(query: query)

            var newTransactions: [Transaction] = []
            var newIds: [String] = []

            for raw in rawTransactions {
                let txId = raw.id.uuidString
                guard !syncedIds.contains(txId) else { continue }
                newTransactions.append(mapToTransaction(raw))
                newIds.append(txId)
            }

            var allIds = Array(syncedIds)
            allIds.append(contentsOf: newIds)
            if allIds.count > 10000 { allIds = Array(allIds.suffix(10000)) }
            UserDefaults.standard.set(allIds, forKey: syncedIdsKey)
            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            UserDefaults.standard.set(totalAutoSynced + newTransactions.count, forKey: totalSyncedKey)

            await MainActor.run {
                lastSyncDate = Date()
                totalAutoSynced += newTransactions.count
                addLog("✅ 同步完成: \(newTransactions.count) 条新交易 (共扫描 \(rawTransactions.count) 条)")
            }
            return newTransactions
        } catch {
            await MainActor.run {
                addLog("❌ 同步失败: \(error.localizedDescription)")
            }
            return []
        }
    }

    func startRealTimeMonitoring(onNewTransaction: @escaping (Transaction) -> Void) {
        guard isAuthorized else { return }
        stopMonitoring()
        isMonitoring = true
        addLog("👁️ 实时监控已启动")

        monitorTask = Task {
            do {
                let sequence = store.transactionUpdates
                for try await change in sequence {
                    if Task.isCancelled { break }
                    switch change {
                    case .inserted(let rawTx):
                        let tx = mapToTransaction(rawTx)
                        await MainActor.run {
                            addLog("💳 新交易: \(tx.merchant) ¥\(String(format: "%.2f", tx.amount))")
                            totalAutoSynced += 1
                            UserDefaults.standard.set(totalAutoSynced, forKey: totalSyncedKey)
                            onNewTransaction(tx)
                        }
                        var ids = UserDefaults.standard.stringArray(forKey: syncedIdsKey) ?? []
                        ids.append(rawTx.id.uuidString)
                        UserDefaults.standard.set(ids, forKey: syncedIdsKey)
                    case .updated(let rawTx):
                        await MainActor.run {
                            addLog("📝 交易更新: \(rawTx.merchantName ?? "未知")")
                        }
                    case .deleted(let rawTx):
                        await MainActor.run {
                            addLog("🗑️ 交易删除: \(rawTx.id)")
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("❌ 监控中断: \(error.localizedDescription)")
                    isMonitoring = false
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }

    private func mapToTransaction(_ raw: FinanceKit.Transaction) -> Transaction {
        let amount = abs(raw.transactionAmount.amount)
        let isIncome = raw.transactionAmount.amount > 0 || raw.creditDebitIndicator == .credit
        let merchant = raw.merchantName ?? raw.originalTransactionDescription ?? "未知商家"
        let category = CSVParser.guessCategory(note: merchant, merchant: merchant, tradeType: "")
        return Transaction(
            type: isIncome ? .income : .expense,
            amount: Double(truncating: amount as NSNumber),
            category: category,
            channel: .bankCard,
            note: raw.originalTransactionDescription ?? "",
            date: raw.transactionDate,
            merchant: merchant
        )
    }

    private func mapAccountType(_ account: FinanceKit.Account) -> String {
        switch account.accountType {
        case .asset: return "储蓄卡"
        case .liability: return "信用卡"
        default: return "其他"
        }
    }

    private func addLog(_ message: String) {
        syncLog.append(SyncLogEntry(message: message))
        if syncLog.count > 50 { syncLog.removeFirst() }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return fmt.string(from: date)
    }
}

#else

// MARK: - 模拟器 Fallback
// 提供空壳实现，确保模拟器上正常编译运行

class FinanceKitMonitor: ObservableObject {
    @Published var isAuthorized = false
    @Published var isMonitoring = false
    @Published var accounts: [FinanceAccount] = []
    @Published var syncLog: [SyncLogEntry] = []
    @Published var lastSyncDate: Date?
    @Published var totalAutoSynced: Int = 0

    static var isAvailable: Bool { false }

    func requestAuthorization() async {
        await MainActor.run {
            syncLog.append(SyncLogEntry(message: "⚠️ FinanceKit 在模拟器上不可用"))
        }
    }

    func loadAccounts() async {}
    func syncNewTransactions() async -> [Transaction] { [] }
    func startRealTimeMonitoring(onNewTransaction: @escaping (Transaction) -> Void) {}
    func stopMonitoring() {}
}

#endif
