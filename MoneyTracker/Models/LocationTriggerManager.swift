import Foundation
import CoreLocation
import UserNotifications

// MARK: - 地理围栏自动化
// 当用户进入特定消费场所区域时，自动弹出快捷记账通知
// 离开时统计本次消费
//
// 用例:
// - 进入超市区域 → 通知"在XX超市消费了吗？点击快速记账"
// - 进入餐厅区域 → 自动标记分类为"餐饮"
// - 离开加油站 → 提醒记录加油费

class LocationTriggerManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationTriggerManager()

    @Published var isEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "LocationTrigger.enabled") }
    }
    @Published var savedPlaces: [SavedPlace] = []
    @Published var recentTriggers: [TriggerEvent] = []

    private let locationManager = CLLocationManager()
    private let maxRegions = 20  // iOS 限制最多 20 个地理围栏

    override init() {
        super.init()
        isEnabled = UserDefaults.standard.bool(forKey: "LocationTrigger.enabled")
        loadSavedPlaces()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - 请求权限
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - 添加常去消费地点
    func addPlace(_ place: SavedPlace) {
        guard savedPlaces.count < maxRegions else { return }
        savedPlaces.append(place)
        savePlaces()

        if isEnabled {
            startMonitoringPlace(place)
        }
    }

    func removePlace(_ place: SavedPlace) {
        stopMonitoringPlace(place)
        savedPlaces.removeAll { $0.id == place.id }
        savePlaces()
    }

    // MARK: - 启动/停止全部监控
    func startAllMonitoring() {
        guard CLLocationManager.authorizationStatus() == .authorizedAlways else {
            requestPermission()
            return
        }

        for place in savedPlaces {
            startMonitoringPlace(place)
        }
        isEnabled = true
    }

    func stopAllMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        isEnabled = false
    }

    private func startMonitoringPlace(_ place: SavedPlace) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: place.radius,
            identifier: place.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    private func stopMonitoringPlace(_ place: SavedPlace) {
        for region in locationManager.monitoredRegions {
            if region.identifier == place.id {
                locationManager.stopMonitoring(for: region)
                break
            }
        }
    }

    // MARK: - CLLocationManager Delegate
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let place = savedPlaces.first(where: { $0.id == region.identifier }) else { return }

        let event = TriggerEvent(
            placeId: place.id,
            placeName: place.name,
            category: place.defaultCategory,
            type: .enter,
            date: Date()
        )
        recentTriggers.append(event)

        // 发送"快捷记账"通知
        sendQuickRecordNotification(place: place)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let place = savedPlaces.first(where: { $0.id == region.identifier }) else { return }

        let event = TriggerEvent(
            placeId: place.id,
            placeName: place.name,
            category: place.defaultCategory,
            type: .exit,
            date: Date()
        )
        recentTriggers.append(event)

        // 如果有已知的常用金额，直接自动记账
        if let amount = place.typicalAmount, amount > 0 {
            autoRecord(place: place, amount: amount)
        }
    }

    // MARK: - 发送快捷记账通知（带操作按钮）
    private func sendQuickRecordNotification(place: SavedPlace) {
        let content = UNMutableNotificationContent()
        content.title = "📍 到达 \(place.name)"
        content.body = "点击快速记录\(place.defaultCategory.rawValue)消费"
        content.categoryIdentifier = "QUICK_RECORD"
        content.sound = .default
        content.userInfo = [
            "placeId": place.id,
            "placeName": place.name,
            "category": place.defaultCategory.rawValue,
            "typicalAmount": place.typicalAmount ?? 0,
        ]

        let request = UNNotificationRequest(
            identifier: "location-\(place.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 自动记账（已知常用金额的地点）
    private func autoRecord(place: SavedPlace, amount: Double) {
        let tx = Transaction(
            type: .expense,
            amount: amount,
            category: place.defaultCategory,
            channel: place.defaultChannel,
            note: "自动记账 - \(place.name)",
            date: Date(),
            merchant: place.name
        )

        // 存入待处理队列
        var pending = AutoSyncScheduler.shared.loadPendingTransactions()
        pending.append(tx)
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: "AutoSync.pendingTxs")
        }

        // 发送确认通知
        let content = UNMutableNotificationContent()
        content.title = "✅ 已自动记账"
        content.body = "\(place.name) \(place.defaultCategory.rawValue) ¥\(String(format: "%.1f", amount))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "auto-record-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 注册通知操作（支持通知上直接记账）
    static func registerNotificationActions() {
        let recordAction = UNNotificationAction(
            identifier: "RECORD_ACTION",
            title: "记一笔",
            options: [.foreground]
        )
        let skipAction = UNNotificationAction(
            identifier: "SKIP_ACTION",
            title: "跳过",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: "QUICK_RECORD",
            actions: [recordAction, skipAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - 预设常见地点模板
    static let placeTemplates: [(name: String, category: ExpenseCategory, channel: PaymentChannel, radius: Double)] = [
        ("公司食堂", .food, .wechat, 100),
        ("楼下便利店", .food, .wechat, 50),
        ("常去超市", .shopping, .alipay, 150),
        ("加油站", .transport, .bankCard, 100),
        ("健身房", .entertainment, .bankCard, 100),
        ("地铁站", .transport, .alipay, 200),
        ("医院", .medical, .alipay, 300),
        ("孩子学校", .education, .bankCard, 200),
    ]

    // MARK: - 持久化
    private func savePlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: "LocationTrigger.places")
        }
    }

    private func loadSavedPlaces() {
        if let data = UserDefaults.standard.data(forKey: "LocationTrigger.places"),
           let places = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            savedPlaces = places
        }
    }
}

// MARK: - 保存的消费地点
struct SavedPlace: Identifiable, Codable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double            // 触发半径（米）
    var defaultCategory: ExpenseCategory
    var defaultChannel: PaymentChannel
    var typicalAmount: Double?    // 常用金额（如有则自动记账）
    var autoRecord: Bool          // 是否离开时自动记账

    init(id: String = UUID().uuidString, name: String, latitude: Double, longitude: Double,
         radius: Double = 100, defaultCategory: ExpenseCategory, defaultChannel: PaymentChannel = .wechat,
         typicalAmount: Double? = nil, autoRecord: Bool = false) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.defaultCategory = defaultCategory
        self.defaultChannel = defaultChannel
        self.typicalAmount = typicalAmount
        self.autoRecord = autoRecord
    }
}

// MARK: - 触发事件
struct TriggerEvent: Identifiable {
    let id = UUID()
    let placeId: String
    let placeName: String
    let category: ExpenseCategory
    let type: TriggerType
    let date: Date

    enum TriggerType {
        case enter, exit
    }
}
