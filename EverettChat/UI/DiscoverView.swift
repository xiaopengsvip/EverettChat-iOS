import SwiftUI

/// 发现页（功能列表 → 子页）
struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var featurePage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏（标题居中）
            ZStack {
                Text("发现")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                HStack {
                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            ScrollView {
                VStack(spacing: 0) {
                    FeatureRow(icon: "📡", name: "局域网直连", desc: "同一 Wi-Fi · 配对码/扫描") { featurePage = "lan" }
                    FeatureRow(icon: "☁️", name: "云中继", desc: "公网跨网络 · 在线设备") { featurePage = "relay" }
                    FeatureRow(icon: "📶", name: "蓝牙直连", desc: "近距离 · 无需 Wi-Fi") { featurePage = "bt" }
                    FeatureRow(icon: "🌐", name: "中继网可视化", desc: "实时拓扑 / 在线用户") { featurePage = "topo" }
                    FeatureRow(icon: "🪪", name: "我的二维码", desc: "扫码互加好友") { appState.showMyQr = true }
                    FeatureRow(icon: "📷", name: "扫一扫", desc: "扫描二维码添加好友") { appState.showQrScanner = true }
                }
            }
        }
        .background(Theme.bg)
        .sheet(item: Binding(
            get: { featurePage.map { FeaturePage(rawValue: $0)! } },
            set: { featurePage = $0?.rawValue }
        )) { page in
            FeaturePageView(page: page)
        }
        .sheet(isPresented: $appState.showQrScanner) { QrScannerView() }
        .sheet(isPresented: $appState.showMyQr) { MyQrCodeView() }
    }
}

enum FeaturePage: String, Identifiable {
    case lan = "lan"
    case relay = "relay"
    case bt = "bt"
    case topo = "topo"
    var id: String { rawValue }
}

struct FeatureRow: View {
    let icon: String
    let name: String
    let desc: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.title3)
                VStack(alignment: .leading) {
                    Text(name).font(.body.weight(.medium)).foregroundColor(Theme.textPrimary)
                    Text(desc).font(.caption).foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().overlay(Theme.surfaceHigh).padding(.leading, 56)
    }
}

struct FeaturePageView: View {
    let page: FeaturePage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18)).foregroundColor(Theme.textPrimary) }
                Text(title).font(.headline).foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(Spacing.md)

            Spacer()
            Text("\(title)功能页（开发中）")
                .font(.footnote).foregroundColor(Theme.textTertiary)
            Spacer()
        }
        .background(Theme.bg)
    }

    private var title: String {
        switch page {
        case .lan: return "局域网直连"
        case .relay: return "云中继"
        case .bt: return "蓝牙直连"
        case .topo: return "中继网可视化"
        }
    }
}
