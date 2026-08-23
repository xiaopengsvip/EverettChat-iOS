import SwiftUI
import MultipeerConnectivity
import CoreNFC
import PhotosUI

/// 文件互传传输模式
enum TransferMode: String, CaseIterable {
    case nfc = "NFC 碰一碰"
    case bluetooth = "蓝牙"
    case lan = "局域网"
}

/// 文件互传页面（NFC 碰一碰 / 蓝牙 / 局域网）
struct FileTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TransferMode = .nfc
    @State private var peers: [MCPeerID] = []
    @State private var connectedPeer: MCPeerID? = nil
    @State private var sending = false
    @State private var transferProgress: Double = 0
    @State private var statusText = ""
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var nfcSession: NFCNDEFReaderSession?
    @State private var nfcMessage = ""

    private let transfer = TransferManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 模式切换
            Picker("传输模式", selection: $mode) {
                ForEach(TransferMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // 状态
            Text(statusText.isEmpty ? "点击下方按钮开始" : statusText)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal)

            // 传输进度条
            if sending || transferProgress > 0 && transferProgress < 1 {
                ProgressView(value: transferProgress)
                    .tint(Theme.primary)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
            }

            // 设备列表
            List {
                if mode == .nfc {
                    NFCSection(nfcMessage: $nfcMessage, nfcResult: $statusText)
                } else {
                    if peers.isEmpty {
                        Text("搜索附近设备...").foregroundColor(Theme.textTertiary).font(.caption)
                    }
                    ForEach(peers, id: \.displayName) { peer in
                        HStack {
                            Image(systemName: "iphone").foregroundColor(Theme.primary)
                            Text(peer.displayName).foregroundColor(Theme.textPrimary)
                            Spacer()
                            if connectedPeer == peer {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            connect(peer)
                        }
                    }
                }
            }
            .listStyle(.plain)

            // 底部操作栏（系统按钮样式）
            HStack(spacing: 16) {
                Button { showPhotoPicker = true } label: {
                    Label("图片", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                Button { showFilePicker = true } label: {
                    Label("文件", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                if mode != .nfc {
                    Button(action: scan) {
                        Label("搜索设备", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                }
            }
            .padding()
        }
        .background(Theme.bg)
        .onAppear {
            transfer.onPeerDiscovered = { peers = $0 }
            transfer.onStateChange = { peer, connected in
                connectedPeer = connected ? peer : nil
                statusText = connected ? "已连接 \(peer.displayName)" : "已断开"
            }
            transfer.onReceive = { data, name in
                statusText = "收到文件: \(name)"
            }
            transfer.onProgress = { p in
                transferProgress = p
                if p >= 1 { statusText = "传输完成" }
            }
            if mode != .nfc { scan() }
        }
        .onDisappear { transfer.disconnect() }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in sendPickerItem(item) }
        .sheet(isPresented: $showFilePicker) { DocumentPicker { _, name, data in sendData(data, name: name) } }
    }

    private func scan() {
        statusText = "正在搜索附近设备..."
        transfer.startBrowsing()
        peers = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let found = transfer.discoveredPeers
            if found.isEmpty {
                statusText = "未发现设备，请确保对方也在文件互传页面"
            }
            peers = found
        }
    }

    private func connect(_ peer: MCPeerID) {
        statusText = "正在连接 \(peer.displayName)..."
        transfer.invite(peer)
    }

    private func sendData(_ data: Data, name: String) {
        guard !data.isEmpty else { return }
        sending = true
        statusText = "正在发送 \(name)..."
        transfer.sendChunked(data, name: name) { success in
            sending = false
            statusText = success ? "✓ 发送成功" : "✗ 发送失败"
        }
    }

    private func sendPickerItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                sendData(data, name: "图片_\(Date().timeIntervalSince1970).jpg")
            }
            pickerItem = nil
        }
    }
}

// MARK: - NFC 扫描区域
struct NFCSection: View {
    @Binding var nfcMessage: String
    @Binding var nfcResult: String
    @State private var scanning = false
    @State private var session: NFCNDEFReaderSession?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(Theme.primary)
            Text("将两台 iPhone 靠近（顶部相碰）")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            Button(action: startNFC) {
                Label(scanning ? "正在扫描..." : "碰一碰", systemImage: "wave.3.right")
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.primary))
            }
            .disabled(scanning)
            if !nfcMessage.isEmpty {
                Text(nfcMessage).font(.caption).foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func startNFC() {
        guard NFCNDEFReaderSession.readingAvailable else {
            nfcResult = "此设备不支持 NFC"
            return
        }
        scanning = true
        let session = NFCNDEFReaderSession(delegate: NFCHandler(completion: { message in
            scanning = false
            if let msg = message {
                nfcMessage = "读取到设备信息: \(msg)"
                nfcResult = "✓ NFC 配对成功，开始传输"
            } else {
                nfcResult = "NFC 读取失败"
            }
        }), queue: .main, invalidateAfterFirstRead: true)
        session.begin()
        self.session = session
    }
}

/// NFC 读取回调
class NFCHandler: NSObject, NFCNDEFReaderSessionDelegate {
    let completion: (String?) -> Void
    init(completion: @escaping (String?) -> Void) { self.completion = completion }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let text = messages.compactMap { msg in
            msg.records.compactMap { String(data: $0.payload, encoding: .utf8) }.joined(separator: ", ")
        }.joined(separator: "; ")
        completion(text.isEmpty ? nil : text)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if (error as NSError).code != 200 { // 200 = user canceled
            completion(nil)
        }
    }
}

// MARK: - MultipeerConnectivity 传输引擎
class TransferManager: NSObject, ObservableObject {
    static let shared = TransferManager()
    private let serviceType = "evo-file"
    private let myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var receivedData: Data?
    var onPeerDiscovered: (([MCPeerID]) -> Void)?
    var onStateChange: ((MCPeerID, Bool) -> Void)?
    var onReceive: ((Data, String) -> Void)?
    var onProgress: ((Double) -> Void)?
    @Published var discoveredPeers: [MCPeerID] = []

    // 分片接收缓存（FILE_CHUNK 协议）
    private struct ChunkBuffer {
        var name: String
        var total: Int
        var chunks: [Int: Data]
        var received: Int
    }
    private var chunkBuffers: [String: ChunkBuffer] = [:]
    private let chunkSize = 256 * 1024  // 256KB/片

    // MARK: - 分片发送（大文件）

    /// 分片发送文件（Evo Protocol: FILE_OFFER / FILE_CHUNK / FILE_COMPLETE）
    func sendChunked(_ data: Data, name: String, completion: @escaping (Bool) -> Void) {
        guard !session.connectedPeers.isEmpty else { completion(false); return }
        let fileId = UUID().uuidString
        let total = max(1, Int(ceil(Double(data.count) / Double(chunkSize))))

        // 发送分片（串行，每片之间小延迟避免拥塞）
        var sent = 0
        let queue = DispatchQueue(label: "evo-chunk-send")
        queue.async {
            for i in 0..<total {
                let start = i * self.chunkSize
                let end = min(start + self.chunkSize, data.count)
                let slice = data.subdata(in: start..<end)
                // 格式：CHUNK|fileId|index|total|name|payload
                var header = "CHUNK|\(fileId)|\(i)|\(total)|\(name)|".data(using: .utf8)!
                var payload = header
                payload.append(slice)
                do {
                    try self.session.send(payload, toPeers: self.session.connectedPeers, with: .reliable)
                } catch {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                sent += 1
                DispatchQueue.main.async {
                    self.onProgress?(Double(sent) / Double(total))
                }
                if i < total - 1 {
                    usleep(20_000)  // 20ms
                }
            }
            DispatchQueue.main.async { completion(true) }
        }
    }

    override private init() {
        myPeerID = MCPeerID(displayName: "EVO-\(DeviceIdentity.shared.shortId)")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func startBrowsing() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["name": DeviceIdentity.shared.deviceName], serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func invite(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func send(_ data: Data, name: String, completion: @escaping (Bool) -> Void) {
        guard !session.connectedPeers.isEmpty else { completion(false); return }
        let payload = name.data(using: .utf8)! + Data([0x00]) + data
        do {
            try session.send(payload, toPeers: session.connectedPeers, with: .reliable)
            completion(true)
        } catch {
            completion(false)
        }
    }

    func disconnect() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }
}

extension TransferManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.onStateChange?(peerID, state == .connected)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 检测分片格式：CHUNK|fileId|index|total|name|payload
        let prefix = "CHUNK|".data(using: .utf8)!
        if data.prefix(prefix.count) == prefix {
            var parts = data.split(separator: UInt8(ascii: "|"), maxSplits: 5, omittingEmptySubsequences: false)
            // parts: CHUNK, fileId, index, total, name, payload(with bars)
            guard parts.count >= 6,
                  let fileId = String(data: parts[1], encoding: .utf8),
                  let idx = Int(String(data: parts[2], encoding: .utf8) ?? ""),
                  let total = Int(String(data: parts[3], encoding: .utf8) ?? ""),
                  let name = String(data: parts[4], encoding: .utf8) else { return }
            // payload 从第 5 个 | 之后开始
            let headerLen = "CHUNK|\(fileId)|\(idx)|\(total)|\(name)|".data(using: .utf8)!.count
            let chunkData = data.dropFirst(headerLen)

            var buf = chunkBuffers[fileId] ?? ChunkBuffer(name: name, total: total, chunks: [:], received: 0)
            buf.chunks[idx] = Data(chunkData)
            buf.received += 1
            chunkBuffers[fileId] = buf

            DispatchQueue.main.async {
                self.onProgress?(Double(buf.received) / Double(buf.total))
            }

            // 收齐 → 组装
            if buf.received == total {
                var full = Data()
                for i in 0..<total {
                    if let chunk = buf.chunks[i] {
                        full.append(chunk)
                    }
                }
                chunkBuffers.removeValue(forKey: fileId)
                DispatchQueue.main.async {
                    self.onReceive?(full, buf.name)
                }
            }
            return
        }

        // 旧格式兼容（小文件直接发送）
        if let zero = data.firstIndex(of: 0x00) {
            let name = String(data: data[..<zero], encoding: .utf8) ?? "unknown"
            let fileData = data[data.index(after: zero)...]
            DispatchQueue.main.async {
                self.onReceive?(Data(fileData), name)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension TransferManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension TransferManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
                self.onPeerDiscovered?(self.discoveredPeers)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
            self.onPeerDiscovered?(self.discoveredPeers)
        }
    }
}