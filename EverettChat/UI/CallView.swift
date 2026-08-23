import SwiftUI

/// 通话界面（全屏，来电/去电/通话中）
struct CallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var call = CallManager.shared

    var body: some View {
        ZStack {
            // 背景色随状态变化
            (stateColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 60)

                // 头像
                LivingAvatarBubble(state: call.state == .ringing ? .listening : (call.state == .inCall ? .speaking : .idle), size: 100)
                    .frame(width: 100, height: 100)

                // 对方名称
                Text(call.peerName)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                // 状态文字
                VStack(spacing: 4) {
                    Text(call.state.label)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    if call.state == .inCall || call.state == .connecting {
                        Text(call.durationString())
                            .font(.system(.title, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 40) {
                    // 静音
                    if call.state == .inCall {
                        CallButton(icon: call.isMuted ? "mic.slash.fill" : "mic.fill", color: call.isMuted ? .red : .white.opacity(0.3)) {
                            call.toggleMute()
                        }
                    }
                    // 挂断/拒绝
                    CallButton(icon: "phone.down.fill", color: .red, size: 60) {
                        if call.state == .ringing {
                            call.rejectCall()
                        } else {
                            call.endCall()
                        }
                        dismiss()
                    }
                    // 接听
                    if call.state == .ringing {
                        CallButton(icon: "phone.fill", color: .green, size: 60) {
                            call.acceptCall()
                        }
                    }
                    // 扬声器
                    if call.state == .inCall {
                        CallButton(icon: call.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill", color: .white.opacity(0.3)) {
                            call.toggleSpeaker()
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer().frame(height: 40)
            }
        }
        .onAppear {
            // 如果有人来电但当前不在通话页，显示
            if call.state == .ended {
                dismiss()
            }
        }
        .onChange(of: call.state) { state in
            if state == .idle || state == .ended {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        }
    }

    private var stateColor: Color {
        call.state == .ringing ? Color(hex: 0x1A1A2E) : Color(hex: 0x0A0A0F)
    }
}

/// 通话圆按钮
struct CallButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                )
        }
        .buttonStyle(.plain)
    }
}