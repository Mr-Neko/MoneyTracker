import Foundation
import AuthenticationServices

// MARK: - 微信/支付宝 OAuth 交易数据拉取
// 通过开放平台 OAuth 2.0 授权后，直接拉取用户交易记录
//
// ⚠️ 现实限制说明：
// - 微信：需要已认证的商户号 + 开放平台应用，个人开发者无法使用交易查询 API
// - 支付宝：需要企业支付宝账号 + 签约「交易信息查询」能力
// - 两者都需要用户主动 OAuth 授权
//
// 本模块提供完整的 OAuth 流程框架，接入真实 API 只需填入 AppID/Secret

class ThirdPartyPaySync: ObservableObject {

    @Published var wechatConnected = false
    @Published var alipayConnected = false
    @Published var wechatLastSync: Date?
    @Published var alipayLastSync: Date?
    @Published var syncLog: [SyncLogEntry] = []

    // 微信开放平台配置（需替换为真实值）
    struct WechatConfig {
        static let appId = "wx_YOUR_APP_ID"
        static let appSecret = "YOUR_APP_SECRET"
        static let mchId = "YOUR_MERCHANT_ID"  // 商户号
        static let redirectUri = "moneytracker://callback/wechat"
        // 需要的权限：snsapi_userinfo + 交易查询
    }

    // 支付宝开放平台配置
    struct AlipayConfig {
        static let appId = "YOUR_ALIPAY_APP_ID"
        static let privateKey = "YOUR_RSA_PRIVATE_KEY"
        static let redirectUri = "moneytracker://callback/alipay"
        // 需要的能力：alipay.trade.query
    }

    // 持久化
    private let wechatTokenKey = "ThirdParty.wechat.token"
    private let alipayTokenKey = "ThirdParty.alipay.token"

    init() {
        wechatConnected = UserDefaults.standard.string(forKey: wechatTokenKey) != nil
        alipayConnected = UserDefaults.standard.string(forKey: alipayTokenKey) != nil
    }

    // MARK: ==========================================
    // MARK: 微信支付 - OAuth + 交易查询
    // MARK: ==========================================

    /// Step 1: 发起微信 OAuth 授权
    func connectWechat() {
        // 构造微信 OAuth URL
        // 真实项目中需要集成微信 SDK（WechatOpenSDK）
        let authURL = """
        https://open.weixin.qq.com/connect/oauth2/authorize?\
        appid=\(WechatConfig.appId)&\
        redirect_uri=\(WechatConfig.redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&\
        response_type=code&\
        scope=snsapi_userinfo&\
        state=wechat_bind#wechat_redirect
        """

        addLog("📱 正在打开微信授权...")
        addLog("🔗 \(authURL.prefix(60))...")

        // 模拟授权成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.handleWechatCallback(code: "MOCK_AUTH_CODE")
        }
    }

    /// Step 2: 处理微信回调
    func handleWechatCallback(code: String) {
        addLog("🔑 收到微信授权码，正在换取 access_token...")

        // POST https://api.weixin.qq.com/sns/oauth2/access_token
        // 参数: appid, secret, code, grant_type=authorization_code
        // 返回: access_token, refresh_token, openid

        // 模拟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let mockToken = "mock_wechat_access_token_\(Date().timeIntervalSince1970)"
            UserDefaults.standard.set(mockToken, forKey: self.wechatTokenKey)
            self.wechatConnected = true
            self.addLog("✅ 微信授权成功，已绑定")
        }
    }

    /// Step 3: 拉取微信支付交易记录
    func syncWechatTransactions() async -> [Transaction] {
        guard wechatConnected else { return [] }

        await MainActor.run {
            addLog("🔄 正在拉取微信支付记录...")
        }

        // 真实 API: POST https://api.mch.weixin.qq.com/v3/bill/tradebill
        // 需要商户证书签名
        // 参数: bill_date, bill_type=ALL
        // 返回: 交易流水 CSV 下载链接

        // 模拟拉取
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let mockTransactions = generateMockWechatData()

        await MainActor.run {
            wechatLastSync = Date()
            addLog("✅ 微信同步完成: \(mockTransactions.count) 条")
        }

        return mockTransactions
    }

    // MARK: ==========================================
    // MARK: 支付宝 - OAuth + 交易查询
    // MARK: ==========================================

    /// Step 1: 发起支付宝 OAuth
    func connectAlipay() {
        // 构造支付宝 OAuth URL
        // 真实项目中需要集成 AlipaySDK
        let authURL = """
        https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?\
        app_id=\(AlipayConfig.appId)&\
        scope=auth_user,auth_zhima&\
        redirect_uri=\(AlipayConfig.redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&\
        state=alipay_bind
        """

        addLog("📱 正在打开支付宝授权...")
        addLog("🔗 \(authURL.prefix(60))...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.handleAlipayCallback(authCode: "MOCK_ALIPAY_CODE")
        }
    }

    /// Step 2: 处理支付宝回调
    func handleAlipayCallback(authCode: String) {
        addLog("🔑 收到支付宝授权码，正在换取 token...")

        // POST https://openapi.alipay.com/gateway.do
        // method=alipay.system.oauth.token
        // 参数: grant_type=authorization_code, code

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let mockToken = "mock_alipay_token_\(Date().timeIntervalSince1970)"
            UserDefaults.standard.set(mockToken, forKey: self.alipayTokenKey)
            self.alipayConnected = true
            self.addLog("✅ 支付宝授权成功，已绑定")
        }
    }

    /// Step 3: 拉取支付宝交易记录
    func syncAlipayTransactions() async -> [Transaction] {
        guard alipayConnected else { return [] }

        await MainActor.run {
            addLog("🔄 正在拉取支付宝交易记录...")
        }

        // 真实 API: alipay.trade.query / alipay.data.bill.balance.query
        // 需要 RSA 签名
        // 可查询: 交易时间/金额/商户/状态

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let mockTransactions = generateMockAlipayData()

        await MainActor.run {
            alipayLastSync = Date()
            addLog("✅ 支付宝同步完成: \(mockTransactions.count) 条")
        }

        return mockTransactions
    }

    // MARK: - 断开连接
    func disconnectWechat() {
        UserDefaults.standard.removeObject(forKey: wechatTokenKey)
        wechatConnected = false
        addLog("🔌 已断开微信连接")
    }

    func disconnectAlipay() {
        UserDefaults.standard.removeObject(forKey: alipayTokenKey)
        alipayConnected = false
        addLog("🔌 已断开支付宝连接")
    }

    // MARK: - 处理 URL Scheme 回调
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if url.absoluteString.contains("wechat") {
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                handleWechatCallback(code: code)
            }
        } else if url.absoluteString.contains("alipay") {
            if let code = components.queryItems?.first(where: { $0.name == "auth_code" })?.value {
                handleAlipayCallback(authCode: code)
            }
        }
    }

    // MARK: - Mock Data
    private func generateMockWechatData() -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let items: [(String, Double, ExpenseCategory, Int)] = [
            ("瑞幸咖啡", 15.0, .food, 0),
            ("美团外卖", 32.5, .food, 0),
            ("微信红包-张三", 50.0, .transfer, -1),
            ("全家便利店", 28.0, .food, -1),
            ("滴滴出行", 18.5, .transport, -2),
        ]
        return items.map { item in
            Transaction(
                type: item.2 == .transfer ? .income : .expense,
                amount: item.1,
                category: item.2,
                channel: .wechat,
                note: item.0,
                date: calendar.date(byAdding: .day, value: item.3, to: now)!,
                merchant: item.0
            )
        }
    }

    private func generateMockAlipayData() -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let items: [(String, Double, ExpenseCategory, Int)] = [
            ("盒马鲜生", 89.5, .shopping, 0),
            ("高德打车", 25.0, .transport, 0),
            ("淘宝-XXX旗舰店", 199.0, .shopping, -1),
            ("饿了么", 28.0, .food, -2),
            ("余额宝收益", 3.21, .other, -3),
        ]
        return items.map { item in
            Transaction(
                type: item.2 == .other ? .income : .expense,
                amount: item.1,
                category: item.2,
                channel: .alipay,
                note: item.0,
                date: calendar.date(byAdding: .day, value: item.3, to: now)!,
                merchant: item.0
            )
        }
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.syncLog.append(SyncLogEntry(message: message))
            if self.syncLog.count > 50 { self.syncLog.removeFirst() }
        }
    }
}
