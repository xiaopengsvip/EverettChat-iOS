import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import PhotosUI

/// 我的二维码页（生成 + 保存相册）
struct MyQrCodeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var showSaved = false

    private let context = CIContext()

    var body: some View {
        VStack(spacing: Spacing.xl) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18)).foregroundColor(Theme.textPrimary) }
                Text("我的二维码").font(.headline).foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(Spacing.md)

            Spacer()

            // 二维码
            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: Radius.large).fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 12)
            } else {
                RoundedRectangle(cornerRadius: Radius.large).fill(Theme.surfaceHigh)
                    .frame(width: 280, height: 280)
                    .overlay(ProgressView())
            }

            Text(appState.deviceName)
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("ID: \(String(appState.deviceId.prefix(8)))")
                .font(.footnote.monospaced())
                .foregroundColor(Theme.textTertiary)

            // 保存相册
            Button {
                guard let img = qrImage else { return }
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                showSaved = true
            } label: {
                Label("保存到相册", systemImage: "square.and.arrow.down")
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Theme.primary))
            }
            .alert("已保存到相册", isPresented: $showSaved) {
                Button("好", role: .cancel) {}
            }

            Text("让对方打开「消息 / 通讯录」右上角 +，点击「扫一扫」扫描此二维码即可添加好友")
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
        .background(Theme.bg)
        .onAppear { generateQR() }
    }

    /// 生成二维码（协议与 Android 一致：{"t":"evt","id":...,"n":...}）
    private func generateQR() {
        let content = "{\"t\":\"evt\",\"id\":\"\(appState.deviceId)\",\"n\":\"\(appState.deviceName)\"}"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return }
        qrImage = UIImage(cgImage: cg)
    }
}

/// 二维码扫描（相机 + 相册 + 我的二维码 + 手电筒补光）
struct QrScannerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = true
    @State private var scanResult: String? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var scanLineOffset: CGFloat = -110
    @State private var showMyQr = false
    @State private var torchOn = false
    @State private var lowLight = false

    var body: some View {
        ZStack {
            CameraPreview(isScanning: $isScanning, torchOn: $torchOn, lowLight: $lowLight) { code in
                scanResult = code
                isScanning = false
            }
            .ignoresSafeArea()

            // 暗光遮罩（弱光提示）
            if lowLight {
                Color.black.opacity(0.15).ignoresSafeArea()
            }

            // 取景框 + 四角
            ZStack {
                RoundedRectangle(cornerRadius: Radius.large)
                    .stroke(Theme.primary, lineWidth: 2)
                    .frame(width: 260, height: 260)
                // 扫描线动画
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.primary.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 240, height: 3)
                    .offset(y: scanLineOffset)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            scanLineOffset = 110
                        }
                    }
                // 四角标记
                ForEach([(x: -1, y: -1), (x: 1, y: -1), (x: -1, y: 1), (x: 1, y: 1)], id: \.x) { corner in
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.primary, lineWidth: 4)
                        .frame(width: 26, height: 26)
                        .offset(x: CGFloat(corner.x) * 130, y: CGFloat(corner.y) * 130)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                            .padding(10).background(Circle().fill(.black.opacity(0.5)))
                    }
                    .padding()
                }
                Spacer()
                // 底部：我的二维码 + 相册扫码 + 手电筒
                HStack(spacing: 20) {
                    // 我的二维码
                    Button {
                        showMyQr = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "qrcode")
                            Text("我的二维码").font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(16)
                    }

                    // 手电筒补光（暗光提醒）
                    Button {
                        torchOn.toggle()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            Text("手电筒").font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(torchOn ? Theme.primary.opacity(0.8) : .black.opacity(0.5))
                        .cornerRadius(16)
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                            Text("相册").font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(16)
                    }
                    .onChange(of: pickerItem) { item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data),
                               let ci = CIImage(image: img),
                               let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                               let features = detector.features(in: ci) as? [CIQRCodeFeature],
                               let msg = features.first?.messageString {
                                scanResult = msg
                            }
                            pickerItem = nil
                        }
                    }
                }
                // 暗光提示条
                if lowLight {
                    Text("环境光线较暗，建议打开手电筒补光")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.4))
        }
        }
        .fullScreenCover(isPresented: $showMyQr) {
            MyQrCodeView()
        }
        .onChange(of: scanResult) { code in
            guard let code else { return }
            handleScan(code)
        }
    }

    private func handleScan(_ content: String) {
        // 解析：{"t":"evt","id":...,"n":...}
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["t"] as? String == "evt",
              let targetId = json["id"] as? String,
              let targetName = json["n"] as? String else {
            // 非好友码
            dismiss()
            return
        }
        if targetId == appState.deviceId {
            dismiss()
            return
        }
        dismiss()
        // 已是好友 → 直接进入聊天；否则发请求
        if appState.contacts.contains(where: { $0.deviceId == targetId }) {
            appState.openPeerChat(name: targetName, peerId: targetId)
        } else {
            appState.sendFriendRequest(targetId: targetId, targetName: targetName)
        }
    }
}

/// 相机预览 + 二维码识别 + 手电筒 + 光线检测
struct CameraPreview: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    @Binding var torchOn: Bool
    @Binding var lowLight: Bool
    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onDetect = onDetect
        vc.onTorchChange = { torchOn = $0 }
        vc.onLowLightChange = { lowLight = $0 }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.isScanning = isScanning
        uiViewController.setTorch(torchOn)
    }
}

final class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?
    var onTorchChange: ((Bool) -> Void)?
    var onLowLightChange: ((Bool) -> Void)?
    var isScanning = true
    private var captureSession: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var lowLightTimer: Timer?
    private var torch = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        startLowLightMonitor()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lowLightTimer?.invalidate()
        setTorch(false)
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device
        let session = AVCaptureSession()
        let output = AVCaptureMetadataOutput()
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// 手电筒开关
    func setTorch(_ on: Bool) {
        torch = on
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    /// 光线监测：每 1.5s 读取亮度，< 0.15 判定暗光
    private func startLowLightMonitor() {
        lowLightTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, let device = self.device else { return }
            let level = device.exposureTargetBias > 0 ? 0.3 : (device.iso > 1000 ? 0.1 : 0.5)
            let dark = level < 0.2
            self.onLowLightChange?(dark)
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isScanning,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        isScanning = false
        onDetect?(value)
    }
}
