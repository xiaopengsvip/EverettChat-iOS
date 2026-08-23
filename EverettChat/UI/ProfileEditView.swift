import SwiftUI
import PhotosUI

/// 个人资料页：头像 / 名称 / 个性签名 / 设备名称
struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ProfileStore.shared
    @State private var name = ""
    @State private var signature = ""
    @State private var deviceName = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 头像（点击更换）
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 8) {
                            if let img = store.myAvatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Theme.surfaceAlt)
                                    .frame(width: 100, height: 100)
                                    .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundColor(Theme.textSecondary))
                            }
                            Text("点击更换头像")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .onChange(of: pickerItem) { item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                store.setAvatar(from: img)
                            }
                            pickerItem = nil
                        }
                    }
                    .padding(.top, 20)

                    // 资料卡片
                    VStack(spacing: 0) {
                        ProfileFieldRow(icon: "person.text.rectangle", label: "昵称") {
                            TextField("请输入昵称", text: $name)
                                .textFieldStyle(.plain)
                                .foregroundColor(Theme.textPrimary)
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        ProfileFieldRow(icon: "pencil", label: "个性签名") {
                            TextField("介绍一下自己吧", text: $signature)
                                .textFieldStyle(.plain)
                                .foregroundColor(Theme.textPrimary)
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        ProfileFieldRow(icon: "iphone", label: "设备名称") {
                            TextField("设备名称", text: $deviceName)
                                .textFieldStyle(.plain)
                                .foregroundColor(Theme.textPrimary)
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        ProfileFieldRow(icon: "number", label: "我的 ID") {
                            Text(DeviceIdentity.shared.shortId)
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: Radius.medium).stroke(Theme.outline, lineWidth: 1))
                    )
                    .padding(.horizontal, Spacing.lg)

                    if saved {
                        Text("✓ 已保存")
                            .font(.caption)
                            .foregroundColor(Theme.success)
                    }
                }
                .padding(.vertical, Spacing.md)
            }
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.primary)
                        .disabled(saved)
                }
            }
        }
        .background(Theme.bg)
        .onAppear {
            name = store.myProfile.name
            signature = store.myProfile.signature
            deviceName = DeviceIdentity.shared.deviceName
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedSig = signature.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { store.updateMyProfile(name: trimmedName) }
        store.updateMyProfile(signature: trimmedSig)
        if !deviceName.trimmingCharacters(in: .whitespaces).isEmpty {
            DeviceIdentity.shared.setCustomName(deviceName.trimmingCharacters(in: .whitespaces))
        }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { dismiss() }
    }
}

/// 资料字段行
struct ProfileFieldRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(Theme.primary)
                .frame(width: 28)
            Text(label)
                .font(.body)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 76, alignment: .leading)
            content()
            Spacer()
        }
        .padding(Spacing.lg)
    }
}
