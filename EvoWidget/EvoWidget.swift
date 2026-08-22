import SwiftUI
import WidgetKit

/// EVO 小组件：AI 状态 / 最近会话
struct EvoWidgetEntry: TimelineEntry {
    let date: Date
    var aiStatus: String = "在线"
    var lastConversation: String = "AI 助手"
    var lastText: String = "你好，我是 EVO"
}

struct EvoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EvoWidgetEntry {
        EvoWidgetEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (EvoWidgetEntry) -> Void) {
        completion(EvoWidgetEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EvoWidgetEntry>) -> Void) {
        completion(Timeline(entries: [EvoWidgetEntry(date: Date())], policy: .never))
    }
}

struct EvoWidgetView: View {
    let entry: EvoWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x8B72FF))
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                }
                .frame(width: 20, height: 20)
                Text("EVO")
                    .font(.caption.weight(.bold))
                Spacer()
                Circle().fill(.green).frame(width: 6, height: 6)
            }
            Spacer()
            Text(entry.lastConversation)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(entry.lastText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .containerBackground(for: .widget) {
            Color(hex: 0xF7F7F5)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x8B72FF))
                Image(systemName: "sparkles").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("EVO · \(entry.aiStatus)")
                    .font(.subheadline.weight(.bold))
                Text("\(entry.lastConversation)：\(entry.lastText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .containerBackground(for: .widget) {
            Color(hex: 0xF7F7F5)
        }
    }
}

/// Widget 注册入口
struct EvoWidgetBundle: WidgetBundle {
    var body: some Widget {
        EvoWidget()
    }
}

struct EvoWidget: Widget {
    let kind = "EvoWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EvoWidgetProvider()) { entry in
            EvoWidgetView(entry: entry)
        }
        .configurationDisplayName("EVO AI")
        .description("AI 状态与最近会话")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 锁屏 Live Activity 视图（与灵动岛共用）
struct EvoLockScreenLiveActivityView: View {
    let context: ActivityViewContext<EvoActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x8B72FF))
                Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(context.attributes.peerName) · \(context.state.status)")
                    .font(.caption.weight(.semibold))
                if !context.state.stepText.isEmpty {
                    Text(context.state.stepText).font(.caption2).foregroundColor(.secondary)
                }
                ProgressView(value: context.state.progress)
                    .tint(Color(hex: 0x8B72FF))
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .activityBackgroundTint(Color(hex: 0x111114).opacity(0.9))
        .activitySystemActionForegroundColor(.white)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
