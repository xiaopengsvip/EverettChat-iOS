import AVFoundation
import CoreBluetooth
import Combine

/// 音频输出设备信息
struct AudioOutputDevice: Identifiable, Equatable {
    let id: String          // port UID
    let name: String        // 设备名（如 "AirPods Pro"）
    let type: String        // 类型：speaker / wired / bluetooth / receiver
    let isBluetooth: Bool

    var icon: String {
        switch type {
        case "bluetooth": return "headphones"
        case "wired": return "headphones.circle"
        case "receiver": return "phone.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    var typeLabel: String {
        switch type {
        case "bluetooth": return "蓝牙耳机"
        case "wired": return "有线耳机"
        case "receiver": return "听筒"
        default: return "扬声器"
        }
    }
}

/// BLE 扫描到的设备
struct BLEDevice: Identifiable, Equatable {
    let id: String          // identifier
    let name: String
    let rssi: Int
    var isConnected: Bool = false
    var serviceUUIDs: [String] = []
}

/// 设备管理核心：音频路由检测 + BLE 扫描
@MainActor
final class DeviceManager: NSObject, ObservableObject {
    static let shared = DeviceManager()

    // 音频
    @Published var audioOutputs: [AudioOutputDevice] = []
    @Published var currentOutputName: String = ""
    @Published var isHeadsetConnected = false

    // BLE
    @Published var bleDevices: [BLEDevice] = []
    @Published var isScanning = false
    @Published var blePoweredOn = false

    private var central: CBCentralManager!
    private var audioObserver: NSObjectProtocol?

    override init() {
        super.init()
        central = CBCentralManager(delegate: nil, queue: nil)
        central.delegate = self
        refreshAudioRoute()
        audioObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAudioRoute()
        }
    }

    deinit {
        if let audioObserver {
            NotificationCenter.default.removeObserver(audioObserver)
        }
    }

    // MARK: - 音频路由

    /// 读取当前音频输出路由
    func refreshAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        var devices: [AudioOutputDevice] = []
        for out in outputs {
            var type = "speaker"
            var isBt = false
            switch out.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                type = "bluetooth"; isBt = true
            case .headphones, .headsetMic:
                type = "wired"
            case .builtInReceiver:
                type = "receiver"
            case .builtInSpeaker:
                type = "speaker"
            default:
                type = "speaker"
                if out.portType.rawValue.contains("bluetooth") { type = "bluetooth"; isBt = true }
            }
            devices.append(AudioOutputDevice(
                id: out.uid, name: out.portName, type: type, isBluetooth: isBt
            ))
        }
        audioOutputs = devices
        currentOutputName = devices.first?.name ?? "无输出"
        isHeadsetConnected = devices.contains { $0.isBluetooth || $0.type == "wired" }
    }

    /// 切换输出到扬声器 / 恢复默认
    func routeToSpeaker(_ toSpeaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            if toSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
            refreshAudioRoute()
        } catch {
            // 忽略：部分设备不支持强制切换
        }
    }

    // MARK: - BLE 扫描

    func startScan() {
        guard blePoweredOn else { return }
        isScanning = true
        bleDevices = []
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // 5 秒后自动停止
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.stopScan()
        }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }
}

// MARK: - CBCentralManagerDelegate

extension DeviceManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        blePoweredOn = central.state == .poweredOn
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "未知设备"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []
        let device = BLEDevice(id: peripheral.identifier.uuidString, name: name,
                               rssi: RSSI.intValue, isConnected: peripheral.state == .connected,
                               serviceUUIDs: services)
        if let idx = bleDevices.firstIndex(where: { $0.id == device.id }) {
            bleDevices[idx] = device
        } else {
            bleDevices.append(device)
        }
        bleDevices.sort { $0.rssi > $1.rssi }
    }
}
