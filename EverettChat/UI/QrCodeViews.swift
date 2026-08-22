import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

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

/// 二维码扫描（相机）
struct QrScannerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = true
    @State private var scanResult: String? = nil

    var body: some View {
        ZStack {
            CameraPreview(isScanning: $isScanning) { code in
                scanResult = code
                isScanning = false
            }
            .ignoresSafeArea()

            // 取景框
            RoundedRectangle(cornerRadius: Radius.large)
                .stroke(Theme.primary, lineWidth: 2)
                .frame(width: 260, height: 260)

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
                Text("扫描好友二维码")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.5))
            }
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

/// 相机预览 + 二维码识别
struct CameraPreview: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onDetect = onDetect
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.isScanning = isScanning
    }
}

final class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?
    var isScanning = true
    private var captureSession: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
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

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isScanning,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        isScanning = false
        onDetect?(value)
    }
}
