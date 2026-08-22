import ActivityKit
import SwiftUI
import WidgetKit

/// EVO Live Activity：灵动岛 + 锁屏
struct EvoLiveActivityView: View {
    let context: ActivityViewContext<EvoActivityAttributes>
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        switch context.state.isFinished {
        case true: finishedView
        default: activeView
        }
    }

    // MARK: - 活跃状态
    private var activeView: some View {
        HStack(spacing: 10) {
            // EVO 品牌图标
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0x8B72FF))
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.attributes.peerName) · \(context.state.status)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x171717))
                    .lineLimit(1)
                if !context.state.stepText.isEmpty {
                    Text(context.state.stepText)
                        .font(.caption2)
                        .foregroundColor(dark ? Color(hex: 0xA1A1A6) : Color(hex: 0x6F7075))
                        .lineLimit(1)
                }
                if !context.state.fileName.isEmpty {
                    Text(context.state.fileName)
                        .font(.system(size: 10))
                        .foregroundColor(dark ? Color(hex: 0x6E6E73) : Color(hex: 0x9A9BA0))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            progressRing
        }
        .padding(.horizontal, 12)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(context.state.progress, 0), 1)))
                .stroke(Color(hex: 0x8B72FF), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(context.state.progress * 100))%")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x171717))
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - 完成状态
    private var finishedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
            Text("任务完成")
                .font(.caption.weight(.semibold))
                .foregroundColor(dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x171717))
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

/// 灵动岛紧凑区域（左侧）
struct EvoCompactLeadingView: View {
    let state: EvoActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x8B72FF))
            Image(systemName: state.isFinished ? "checkmark" : "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 22, height: 22)
    }
}

/// 灵动岛紧凑区域（右侧）
struct EvoCompactTrailingView: View {
    let state: EvoActivityAttributes.ContentState
    var body: some View {
        Text(state.isFinished ? "完成" : "\(Int(state.progress * 100))%")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
    }
}

/// 灵动岛极小区域
struct EvoMinimalView: View {
    let state: EvoActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x8B72FF))
            Image(systemName: state.isFinished ? "checkmark" : "sparkles")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 16, height: 16)
    }
}

/// Live Activity 注册入口
struct EvoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EvoActivityAttributes.self) { context in
            // 灵动岛
            EvoLiveActivityView(context: context)
                .activityBackgroundTint(Color(hex: 0x111114).opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开区域
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x8B72FF))
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    }
                    .frame(width: 30, height: 30)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.status)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(hex: 0xF5F5F7))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if !context.state.stepText.isEmpty {
                            Text(context.state.stepText).font(.caption2).foregroundColor(Color(hex: 0xA1A1A6))
                        }
                        if !context.state.fileName.isEmpty {
                            Text(context.state.fileName).font(.system(size: 10)).foregroundColor(Color(hex: 0x6E6E73)).lineLimit(1)
                        }
                        ProgressView(value: context.state.progress)
                            .tint(Color(hex: 0x8B72FF))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.toolName.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver").font(.system(size: 11))
                            Text("工具：\(context.state.toolName)").font(.caption2)
                            Spacer()
                        }
                        .foregroundColor(Color(hex: 0x8B72FF))
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                EvoCompactLeadingView(state: context.state)
            } compactTrailing: {
                EvoCompactTrailingView(state: context.state)
            } minimal: {
                EvoMinimalView(state: context.state)
            }
            .widgetURL(URL(string: "evo://chat/\(context.attributes.sessionId)"))
            .keylineTint(Color(hex: 0x8B72FF))
        }
    }

    private func dark(isDark: Bool) -> Color {
        isDark ? Color(hex: 0x111114).opacity(0.9) : Color(hex: 0xF7F7F5).opacity(0.85)
    }
}
