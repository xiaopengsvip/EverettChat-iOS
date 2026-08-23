import SwiftUI

/// Evo Living Avatar 状态机
enum AvatarState {
    case idle        // 待机：呼吸 + 眨眼 + 头发微动
    case thinking    // 思考：紫色轨道 + 波形 + 眼神微动
    case speaking    // 说话：光环脉冲 + 嘴部开合
    case listening   // 聆听：柔光增强 + 眼睛聚焦
    case happy       // 开心：微笑 + 星光

    var isDark: Bool { AppTheme.isDark }
}

/// Evo Living Avatar — 可呼吸的 AI 数字头像
/// 高保真矢量绘制：黑发 / 黑框眼镜 / 白衬衫 + Liquid Glass 光环 + 微动画
struct LivingAvatar: View {
    var state: AvatarState = .idle
    var size: CGFloat = 72

    @State private var blinkPhase = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let cx = w / 2

                // ==== Liquid Glass 光环（呼吸 + 状态色） ====
                let haloPulse = 0.5 + 0.5 * sin(t * 1.2)              // 呼吸
                let haloBase = 0.72 + haloPulse * 0.18
                let speakingPulse = state == .speaking ? 0.5 + 0.5 * sin(t * 8) : 0.0
                let thinkingGlow = state == .thinking ? 0.5 + 0.5 * sin(t * 3) : 0.0
                let ringColor = Color(hex: 0x8B72FF).opacity(haloBase + speakingPulse * 0.2 + thinkingGlow * 0.15)

                // 外层光环
                var haloRect = CGRect(x: w * 0.08, y: h * 0.06, width: w * 0.84, height: h * 0.84)
                context.fill(Path(ellipseIn: haloRect), with: .color(ringColor.opacity(0.10)))
                context.stroke(Path(ellipseIn: haloRect.insetBy(dx: 2, dy: 2)), with: .color(ringColor.opacity(0.35)), lineWidth: 1.5)

                // 流动轨道点（思考时旋转）
                if state == .thinking {
                    for i in 0..<3 {
                        let ang = t * 0.8 + Double(i) * 2.094
                        let px = cx + cos(ang) * w * 0.40
                        let py = h * 0.50 + sin(ang) * h * 0.36
                        let dotR = 2.5 + thinkingGlow * 2
                        context.fill(
                            Path(ellipseIn: CGRect(x: px - dotR, y: py - dotR, width: dotR * 2, height: dotR * 2)),
                            with: .color(Color(hex: 0x8B72FF).opacity(0.8))
                        )
                    }
                }

                // ==== 呼吸（整体缩放） ====
                let breath = 1.0 + 0.012 * sin(t * 1.4)
                context.translateBy(x: cx, y: h * 0.52)
                context.scaleBy(x: breath, y: breath)
                context.translateBy(x: -cx, y: -h * 0.52)

                // ==== 身体：白衬衫 ====
                let bodyRect = CGRect(x: w * 0.28, y: h * 0.74, width: w * 0.44, height: h * 0.22)
                context.fill(Path(roundedRect: bodyRect, cornerRadius: w * 0.06), with: .color(.white.opacity(0.92)))
                // 领口 V
                var collar = Path()
                collar.move(to: CGPoint(x: cx - w * 0.06, y: h * 0.74))
                collar.addLine(to: CGPoint(x: cx, y: h * 0.84))
                collar.addLine(to: CGPoint(x: cx + w * 0.06, y: h * 0.74))
                context.fill(collar, with: .color(Color(hex: 0xE8E8EC)))

                // ==== 脖子 ====
                context.fill(
                    Path(roundedRect: CGRect(x: cx - w * 0.075, y: h * 0.60, width: w * 0.15, height: h * 0.16), cornerRadius: w * 0.03),
                    with: .color(Color(hex: 0xF2C9A0))
                )

                // ==== 脸 ====
                let faceRect = CGRect(x: w * 0.22, y: h * 0.16, width: w * 0.56, height: h * 0.50)
                context.fill(Path(roundedRect: faceRect, cornerRadius: w * 0.14), with: .color(Color(hex: 0xF5C9A5)))

                // ==== 头发：黑色蓬松 ====
                var hair = Path()
                hair.move(to: CGPoint(x: w * 0.20, y: h * 0.30))
                hair.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.14), control: CGPoint(x: w * 0.14, y: h * 0.20))
                hair.addQuadCurve(to: CGPoint(x: w * 0.38, y: h * 0.10), control: CGPoint(x: w * 0.28, y: h * 0.08))
                hair.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.10), control: CGPoint(x: w * 0.50, y: h * 0.04))
                hair.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.16), control: CGPoint(x: w * 0.72, y: h * 0.08))
                hair.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.34), control: CGPoint(x: w * 0.88, y: h * 0.24))
                // 头发微动（微幅正弦偏移）
                let hairWave = 0.004 * sin(t * 2.0)
                hair.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.20 + hairWave * h), control: CGPoint(x: w * 0.86, y: h * 0.18))
                hair.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.12), control: CGPoint(x: w * 0.64, y: h * 0.10))
                hair.addQuadCurve(to: CGPoint(x: w * 0.26, y: h * 0.18), control: CGPoint(x: w * 0.36, y: h * 0.08))
                hair.closeSubpath()
                context.fill(hair, with: .color(Color(hex: 0x1C1C1E)))

                // ==== 眼镜：黑框 ====
                let glassY = h * 0.34
                let glassW = w * 0.17
                let glassH = h * 0.09
                // 左镜片
                var lensL = Path(roundedRect: CGRect(x: cx - glassW - w * 0.045, y: glassY, width: glassW, height: glassH), cornerRadius: w * 0.02)
                context.stroke(lensL, with: .color(Color(hex: 0x1C1C1E)), lineWidth: 2.5)
                // 右镜片
                var lensR = Path(roundedRect: CGRect(x: cx + w * 0.045, y: glassY, width: glassW, height: glassH), cornerRadius: w * 0.02)
                context.stroke(lensR, with: .color(Color(hex: 0x1C1C1E)), lineWidth: 2.5)
                // 鼻桥
                var bridge = Path()
                bridge.move(to: CGPoint(x: cx - w * 0.045, y: glassY + glassH * 0.45))
                bridge.addLine(to: CGPoint(x: cx + w * 0.045, y: glassY + glassH * 0.45))
                context.stroke(bridge, with: .color(Color(hex: 0x1C1C1E)), lineWidth: 2)

                // ==== 眼睛（眨眼） ====
                // 眨眼周期 ~3.5s，闭眼瞬间
                let blinkCycle = t.truncatingRemainder(dividingBy: 3.5)
                let eyeClosed = blinkCycle < 0.12
                let eyeOpen = eyeClosed ? 0.12 : 1.0   // 睁眼比例
                let eyeY = glassY + glassH * 0.55
                let eyeW = w * 0.035
                for side in [-1.0, 1.0] {
                    let ex = cx + side * w * 0.115
                    if eyeOpen > 0.5 {
                        // 睁眼：上弧线 + 下弧线
                        var eye = Path()
                        eye.move(to: CGPoint(x: ex - eyeW, y: eyeY))
                        eye.addQuadCurve(to: CGPoint(x: ex + eyeW, y: eyeY), control: CGPoint(x: ex, y: eyeY - eyeW * 1.2))
                        context.stroke(eye, with: .color(Color(hex: 0x1C1C1E)), lineWidth: 1.6)
                        // 瞳孔
                        let pupilR = w * 0.016
                        context.fill(
                            Path(ellipseIn: CGRect(x: ex - pupilR, y: eyeY - pupilR * 0.6, width: pupilR * 2, height: pupilR * 1.6)),
                            with: .color(Color(hex: 0x1C1C1E))
                        )
                    } else {
                        // 闭眼：一条线
                        var line = Path()
                        line.move(to: CGPoint(x: ex - eyeW, y: eyeY))
                        line.addLine(to: CGPoint(x: ex + eyeW, y: eyeY))
                        context.stroke(line, with: .color(Color(hex: 0x1C1C1E)), lineWidth: 1.6)
                    }
                }

                // ==== 嘴巴（说话开合 / 微笑） ====
                let mouthY = h * 0.54
                let mouthW = w * 0.10
                if state == .speaking {
                    let open = 0.10 + 0.10 * abs(sin(t * 6))
                    var mouth = Path(roundedRect: CGRect(x: cx - mouthW, y: mouthY - open * 0.5, width: mouthW * 2, height: open), cornerRadius: open * 0.5)
                    context.fill(mouth, with: .color(Color(hex: 0x8A4A2B)))
                } else if state == .happy {
                    var smile = Path()
                    smile.move(to: CGPoint(x: cx - mouthW, y: mouthY))
                    smile.addQuadCurve(to: CGPoint(x: cx + mouthW, y: mouthY), control: CGPoint(x: cx, y: mouthY + h * 0.035))
                    context.stroke(smile, with: .color(Color(hex: 0x8A4A2B)), lineWidth: 2)
                } else {
                    var mouth = Path()
                    mouth.move(to: CGPoint(x: cx - mouthW * 0.6, y: mouthY))
                    mouth.addQuadCurve(to: CGPoint(x: cx + mouthW * 0.6, y: mouthY), control: CGPoint(x: cx, y: mouthY + h * 0.012))
                    context.stroke(mouth, with: .color(Color(hex: 0x8A4A2B)), lineWidth: 1.6)
                }

                // ==== 思考波形（thinking 时头部上方） ====
                if state == .thinking {
                    for i in 0..<5 {
                        let bx = cx - w * 0.10 + CGFloat(i) * w * 0.05
                        let waveH = (3 + 5 * abs(sin(t * 4 + Double(i)))) * (w / 72)
                        var bar = Path(roundedRect: CGRect(x: bx, y: h * 0.055 - waveH, width: w * 0.022, height: waveH), cornerRadius: 2)
                        context.fill(bar, with: .color(Color(hex: 0x8B72FF).opacity(0.85)))
                    }
                }

                // ==== 开心星光（happy 时） ====
                if state == .happy {
                    for i in 0..<4 {
                        let ang = t * 0.6 + Double(i) * 1.57
                        let sx = cx + cos(ang) * w * 0.42
                        let sy = h * 0.30 + sin(ang) * h * 0.25
                        let twinkle = 0.5 + 0.5 * sin(t * 3 + Double(i) * 2)
                        context.fill(
                            Path(ellipseIn: CGRect(x: sx - 2, y: sy - 2, width: 4, height: 4)),
                            with: .color(Color(hex: 0xFFD700).opacity(0.5 + twinkle * 0.5))
                        )
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// 圆形裁切 + 玻璃光环容器（用于聊天气泡头像）
struct LivingAvatarBubble: View {
    var state: AvatarState = .idle
    var size: CGFloat = 40

    var body: some View {
        LivingAvatar(state: state, size: size)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Theme.outline, lineWidth: 1)
            )
    }
}

#Preview {
    HStack(spacing: 20) {
        LivingAvatarBubble(state: .idle, size: 44)
        LivingAvatarBubble(state: .thinking, size: 44)
        LivingAvatarBubble(state: .speaking, size: 44)
        LivingAvatarBubble(state: .happy, size: 44)
    }
    .padding()
}
