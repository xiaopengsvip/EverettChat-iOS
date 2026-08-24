import SwiftUI
import JavaScriptCore
import CoreLocation
import UIKit

// MARK: - AI 工具卡片（AI 回复中检测标记 → 渲染可交互卡片）

/// AI 工具卡片类型
enum AIToolCard: Identifiable {
    case time          // [工具:时间]  → 时钟 + 年月日日历
    case calendar      // [工具:日历]  → 月份日历
    case weather       // [工具:天气]  → 定位 + 实时天气
    case location      // [工具:定位]  → 经纬度 + 地图
    case code          // ```js ... ```  → 应用内运行

    var id: String {
        switch self {
        case .time: return "time"
        case .calendar: return "calendar"
        case .weather: return "weather"
        case .location: return "location"
        case .code: return "code"
        }
    }
}

/// 从 AI 文本提取工具卡片（顺序：先代码块，后标记）
func extractToolCards(from text: String) -> [(card: AIToolCard, code: String?)] {
    var cards: [(AIToolCard, String?)] = []
    var remaining = text

    // 1. JS 代码块（```js ... ``` 或 ```javascript ... ```）
    let codePattern = #"```(?:js|javascript)\n([\s\S]*?)```"#
    if let regex = try? NSRegularExpression(pattern: codePattern) {
        let nsRange = NSRange(remaining.startIndex..<remaining.endIndex, in: remaining)
        let matches = regex.matches(in: remaining, range: nsRange)
        for match in matches {
            if let range = Range(match.range(at: 1), in: remaining) {
                let code = String(remaining[range])
                cards.append((.code, code))
            }
        }
    }

    // 2. 工具标记
    let marks: [(String, AIToolCard)] = [
        ("[工具:时间]", .time),
        ("[工具:日历]", .calendar),
        ("[工具:天气]", .weather),
        ("[工具:定位]", .location),
    ]
    for (mark, card) in marks {
        if remaining.contains(mark) {
            cards.append((card, nil))
        }
    }
    return cards
}

/// 提取消息中的第一个 URL（用于链接卡片显示）
func extractFirstURL(from text: String) -> String? {
    let pattern = #"(?:https?://)?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?:[/?#][^\s<>"']*)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: nsRange),
          let range = Range(match.range, in: text) else { return nil }
    let raw = String(text[range])
    // 排除纯文本中的小数点/句号结尾
    var cleaned = raw
    while cleaned.hasSuffix(".") || cleaned.hasSuffix(",") || cleaned.hasSuffix("。") {
        cleaned.removeLast()
    }
    return cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") ? cleaned : "https://" + cleaned
}

// MARK: - 时间/日历卡片

/// 实时时钟 + 年月日（Liquid Glass 风格）
struct TimeCard: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            // 时钟
            Text(now, style: .time)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Theme.textPrimary)
            // 年月日 + 星期
            Text(dateString)
                .font(.body)
                .foregroundColor(Theme.textSecondary)
            Text(weekdayString)
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
        .onReceive(timer) { now = $0 }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: now)
    }

    private var weekdayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: now)
    }
}

// MARK: - 日历卡片

/// 当月日历（可切换月份）
struct CalendarCard: View {
    @State private var month = Date()
    private let weekDays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 10) {
            // 月份标题
            HStack {
                Button { month = prevMonth } label: {
                    Image(systemName: "chevron.left").font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button { month = nextMonth } label: {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            // 星期
            HStack {
                ForEach(weekDays, id: \.self) { d in
                    Text(d).font(.caption2).foregroundColor(Theme.textTertiary).frame(maxWidth: .infinity)
                }
            }

            // 日期格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    let inMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.caption)
                        .foregroundColor(inMonth ? (isToday ? .white : Theme.textPrimary) : Theme.textTertiary.opacity(0.3))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(isToday ? Theme.primary : .clear)
                        )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    private var days: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let firstWeekday = cal.component(.weekday, from: first) - 1
        var result: [Date] = []
        for _ in 0..<firstWeekday {
            result.append(first.addingTimeInterval(-86400 * Double(firstWeekday)))
        }
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: first) {
                result.append(d)
            }
        }
        return result
    }

    private var prevMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
    }

    private var nextMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
    }
}

// MARK: - 天气卡片

/// 定位 + 天气（Open-Meteo 免费 API，无需 key）
struct WeatherCard: View {
    @State private var loading = true
    @State private var errorText = ""
    @State private var temperature: Double = 0
    @State private var condition: String = ""
    @State private var city: String = ""
    @State private var location: CLLocationCoordinate2D?

    private let locationManager = LocationProvider.shared

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                HStack(spacing: 8) {
                    EvoLottieView(animationName: EvoLottie.aiToolLoading)
                        .frame(width: 28, height: 28)
                    Text("定位并获取天气...").font(.caption).foregroundColor(Theme.textTertiary)
                }
            } else if !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundColor(Theme.error)
            } else {
                HStack {
                    Image(systemName: conditionIcon)
                        .font(.system(size: 34))
                        .foregroundColor(Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(temperature))°C")
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                        Text("\(city) · \(condition)")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
        .onAppear { fetch() }
    }

    private func fetch() {
        loading = true
        errorText = ""
        locationManager.requestLocation { coord in
            guard let coord else {
                loading = false
                errorText = "无法获取定位（请在设置中允许定位权限）"
                return
            }
            location = coord
            fetchWeather(lat: coord.latitude, lon: coord.longitude)
        }
    }

    private func fetchWeather(lat: Double, lon: Double) {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true&timezone=auto")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                loading = false
                guard let data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = json["current_weather"] as? [String: Any],
                      let temp = current["temperature"] as? Double else {
                    errorText = "天气获取失败"
                    return
                }
                temperature = temp
                let code = current["weathercode"] as? Int ?? 0
                condition = Self.conditionName(code)
                city = "当前位置"
            }
        }.resume()
    }

    private static func conditionName(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...67: return "雨"
        case 71...77: return "雪"
        case 80...82: return "阵雨"
        case 95...99: return "雷暴"
        default: return "未知"
        }
    }

    private var conditionIcon: String {
        switch condition {
        case "晴": return "sun.max.fill"
        case "多云": return "cloud.sun.fill"
        case "阴": return "cloud.fill"
        case "雾": return "cloud.fog.fill"
        case "毛毛雨", "雨", "阵雨": return "cloud.rain.fill"
        case "雪": return "cloud.snow.fill"
        case "雷暴": return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }
}

/// 定位提供者（单例）
class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    private var hasResult = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        hasResult = false
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            completion(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus != .notDetermined {
            completion?(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasResult, let loc = locations.first else { return }
        hasResult = true
        completion?(loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !hasResult else { return }
        hasResult = true
        completion?(nil)
    }
}

// MARK: - 定位卡片

/// 定位卡片（经纬度 + 地图打开）
struct LocationCard: View {
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                HStack(spacing: 8) {
                    EvoLottieView(animationName: EvoLottie.aiToolLoading)
                        .frame(width: 28, height: 28)
                    Text("正在定位...").font(.caption).foregroundColor(Theme.textTertiary)
                }
            } else if let c = coordinate {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.5f, %.5f", c.latitude, c.longitude))
                            .font(.caption.monospaced())
                            .foregroundColor(Theme.textPrimary)
                        Text("点击在地图中打开")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let url = URL(string: "https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)")!
                    UIApplication.shared.open(url)
                }
            } else {
                Text("定位失败（请在设置中允许定位权限）")
                    .font(.caption)
                    .foregroundColor(Theme.error)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
        .onAppear {
            LocationProvider.shared.requestLocation { coord in
                loading = false
                coordinate = coord
            }
        }
    }
}

// MARK: - 代码运行卡片（JavaScriptCore 应用内执行）

/// JS 代码运行器：应用内执行 AI 生成的 JS 代码
struct CodeRunnerCard: View {
    let code: String
    @State private var output = ""
    @State private var hasRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题 + 运行按钮
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.primary)
                Text("JavaScript")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button {
                    runCode()
                } label: {
                    Label(hasRun ? "重新运行" : "运行", systemImage: "play.fill")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.primary))
                }
                .buttonStyle(.plain)
            }

            // 代码
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small)
                        .fill(Theme.surfaceAlt)
                )

            // 输出
            if hasRun {
                Divider().overlay(Theme.outline)
                Text(output.isEmpty ? "完成（无输出）" : output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(output.contains("Error") ? Theme.error : Theme.success)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
    }

    /// JavaScriptCore 执行 JS 代码，捕获 console.log
    private func runCode() {
        let context = JSContext()!
        let logBuffer = NSMutableString()
        context.exceptionHandler = { _, exception in
            logBuffer.append("Error: \(exception?.toString() ?? "unknown")\n")
        }
        let log: @convention(block) (String) -> Void = { msg in
            logBuffer.append(msg)
            logBuffer.append("\n")
        }
        context.setObject(log, forKeyedSubscript: "consoleLog" as NSString)
        context.evaluateScript("""
        var console = { log: function(m) { consoleLog(String(m)) }, 
                        error: function(m) { consoleLog('Error: ' + m) } };
        """)
        context.evaluateScript(code)
        output = logBuffer as String
        hasRun = true
    }
}

// MARK: - 工具卡片容器（按类型渲染）

struct AIToolCardView: View {
    let card: AIToolCard
    var code: String? = nil

    var body: some View {
        switch card {
        case .time:
            TimeCard()
        case .calendar:
            CalendarCard()
        case .weather:
            WeatherCard()
        case .location:
            LocationCard()
        case .code:
            if let code {
                CodeRunnerCard(code: code)
            }
        }
    }
}
