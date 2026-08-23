import Foundation
import UIKit
import Combine

/// 用户资料模型（头像/名称/签名）
struct UserProfile: Codable, Equatable {
    var deviceId: String = ""
    var avatar: String = ""       // 压缩后 base64（200px JPEG）
    var name: String = ""
    var signature: String = ""
    var updatedAt: Date = Date()

    static let empty = UserProfile()
}

/// 资料存储 + 云端同步（/profile）
/// - 自己资料：本地持久化 + 上传云端
/// - 好友资料：缓存（deviceId -> profile），从云端拉取
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var myProfile = UserProfile()
    @Published var friendProfiles: [String: UserProfile] = [:]

    private let defaults = UserDefaults.standard
    private let myKey = "evt_my_profile"
    private let friendsKey = "evt_friend_profiles"
    private let cacheLimit = 200   // 最多缓存 200 个好友资料

    private init() {
        load()
    }

    // MARK: - 本地持久化

    private func load() {
        if let data = defaults.data(forKey: myKey),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            myProfile = p
        } else {
            myProfile = UserProfile(deviceId: DeviceIdentity.shared.deviceId,
                                    avatar: "",
                                    name: DeviceIdentity.shared.deviceName,
                                    signature: "这个人很懒，什么都没写~")
        }
        if let data = defaults.data(forKey: friendsKey),
           let p = try? JSONDecoder().decode([String: UserProfile].self, from: data) {
            friendProfiles = p
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(myProfile) {
            defaults.set(data, forKey: myKey)
        }
        if let data = try? JSONEncoder().encode(friendProfiles) {
            defaults.set(data, forKey: friendsKey)
        }
    }

    // MARK: - 更新自己资料

    /// 更新资料（本地 + 上传云端）
    func updateMyProfile(name: String? = nil, signature: String? = nil, avatar: String? = nil) {
        if let name { myProfile.name = name }
        if let signature { myProfile.signature = signature }
        if let avatar { myProfile.avatar = avatar }
        myProfile.updatedAt = Date()
        save()
        uploadMyProfile()
    }

    /// 选择并压缩头像（200px JPEG）
    func setAvatar(from image: UIImage) {
        let resized = image.resized(maxSide: 200)
        let jpeg = resized.jpegData(compressionQuality: 0.7) ?? Data()
        updateMyProfile(avatar: jpeg.base64EncodedString())
    }

    /// 上传自己的资料到云端
    func uploadMyProfile() {
        guard let url = URL(string: "\(PublicRelay.httpURL)/profile") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceId": myProfile.deviceId.isEmpty ? DeviceIdentity.shared.deviceId : myProfile.deviceId,
            "avatar": myProfile.avatar,
            "name": myProfile.name,
            "signature": myProfile.signature
        ])
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - 好友资料

    /// 获取好友资料（缓存优先，无则拉取云端）
    func profile(for deviceId: String) -> UserProfile? {
        if let cached = friendProfiles[deviceId] { return cached }
        fetchProfile(deviceId)
        return nil
    }

    /// 从云端拉取资料并缓存
    func fetchProfile(_ deviceId: String) {
        guard let url = URL(string: "\(PublicRelay.httpURL)/profile?deviceId=\(deviceId)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else { return }
            let profile = UserProfile(
                deviceId: deviceId,
                avatar: json["avatar"] as? String ?? "",
                name: name,
                signature: json["signature"] as? String ?? ""
            )
            DispatchQueue.main.async {
                self?.friendProfiles[deviceId] = profile
                if let count = self?.friendProfiles.count, count > self?.cacheLimit ?? 200 {
                    self?.friendProfiles.removeAll { $0.key == self?.friendProfiles.keys.first }
                }
                self?.save()
            }
        }.resume()
    }

    /// 好友头像 UIImage（无则 nil）
    func friendAvatar(_ deviceId: String) -> UIImage? {
        guard let profile = friendProfiles[deviceId], !profile.avatar.isEmpty,
              let data = Data(base64Encoded: profile.avatar) else { return nil }
        return UIImage(data: data)
    }

    /// 我的头像 UIImage（无则 nil）
    var myAvatarImage: UIImage? {
        guard !myProfile.avatar.isEmpty, let data = Data(base64Encoded: myProfile.avatar) else { return nil }
        return UIImage(data: data)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(maxSide / size.width, maxSide / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
