import SwiftUI

/// 通话界面（全屏，来电/去电/通话中；视频通话显示远端大画面 + 本地画中画）
struct CallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var call = CallManager.shared
    @ObservedObject private var engine = WebRTCEngine.shared

    var body: some View {
        ZStack {
            // 背景色随状态变化
            (stateColor)
                .ignoresSafeArea()

            if call.callType == .video && (call.state == .connecting || call.state == .inCall) {
                // ===== 视频通话模式：远端大画面 + 本地画中画 =====
                ZStack {
                    // 远端视频（全屏）
                    if engine.remoteVideoView != nil {
                        VideoRendererView(videoView: engine.remoteVideoView)
                            .ignoresSafeArea()
                    } else {
                        // 未拿到远端画面：显示占位
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 72))
                                .foregroundColor(.white.opacity(0.3))
                            Text(call.peerName)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }

                    // 本地画中画（右上角）
                    if engine.localVideoView != nil {
                        VideoRendererView(videoView: engine.localVideoView)
                            .frame(width: 100, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.4), lineWidth: 1))
                            .shadow(radius: 8)
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    // 顶部状态
                    VStack {
                        Text(call.state.label)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.top, 56)
                        Spacer()
                    }
                }
            } else {
                // ===== 语音通话模式：头像 + 状态 =====
                VStack(spacing: 24) {
                    Spacer().frame(height: 60)

                    // 头像
                    LivingAvatarBubble(state: call.state == .ringing ? .listening : (call.state == .inCall ? .speaking : .idle), size: 100)
                        .frame(width: 100, height: 100)

                    // 通话连接动画（connecting 状态显示 Lottie 双环脉冲）
                    if call.state == .connecting {
                        EvoLottieView(animationName: EvoLottie.callConnecting)
                            .frame(width: 90, height: 90)
                            .offset(y: -40)
                    }

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
                }
            }

            // 底部操作按钮（两种模式共用）
            VStack {
                Spacer()
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
                .padding(.bottom, 40)
            }
        }
        .onAppear {
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