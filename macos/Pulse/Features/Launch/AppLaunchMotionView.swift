import SwiftUI

/// Animated ECG / Heartbeat waveform shape
struct ECGHeartbeatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let midY = h * 0.5
        
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: w * 0.22, y: midY))
        // P-wave (small bump)
        path.addQuadCurve(to: CGPoint(x: w * 0.32, y: midY), control: CGPoint(x: w * 0.27, y: midY - h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.38, y: midY))
        // Q-dip
        path.addLine(to: CGPoint(x: w * 0.42, y: midY + h * 0.12))
        // R-peak (sharp spike)
        path.addLine(to: CGPoint(x: w * 0.48, y: midY - h * 0.46))
        // S-valley (sharp plunge)
        path.addLine(to: CGPoint(x: w * 0.54, y: midY + h * 0.32))
        // Baseline return
        path.addLine(to: CGPoint(x: w * 0.58, y: midY))
        // T-wave (smooth recovery curve)
        path.addQuadCurve(to: CGPoint(x: w * 0.74, y: midY), control: CGPoint(x: w * 0.66, y: midY - h * 0.22))
        path.addLine(to: CGPoint(x: w, y: midY))
        
        return path
    }
}

public struct AppLaunchMotionView: View {
    @Binding var isPresented: Bool
    
    @State private var badgeScale: CGFloat = 0.82
    @State private var badgeOpacity: Double = 0.0
    
    @State private var ecgProgress: CGFloat = 0.0
    @State private var ecgGlow: Double = 0.0
    
    @State private var ring1Scale: CGFloat = 0.85
    @State private var ring1Opacity: Double = 0.8
    @State private var ring2Scale: CGFloat = 0.85
    @State private var ring2Opacity: Double = 0.5
    
    @State private var textOffset: CGFloat = 12
    @State private var textOpacity: Double = 0.0
    
    @State private var dismissScale: CGFloat = 1.0
    @State private var dismissOpacity: Double = 1.0
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        ZStack {
            // Dark glass backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            // Ambient Radial Glow
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.18),
                    Color.blue.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Central Pulsing Radar Badge
                ZStack {
                    // Expanding Ring 1
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.6), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ring1Scale)
                        .opacity(ring1Opacity)
                    
                    // Expanding Ring 2
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.4), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(ring2Scale)
                        .opacity(ring2Opacity)
                    
                    // App Icon Card Container
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.15, blue: 0.22),
                                    Color(red: 0.06, green: 0.08, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.7), Color.blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: Color.cyan.opacity(0.35), radius: 24, x: 0, y: 8)
                    
                    // Animated ECG Heartbeat Line
                    ECGHeartbeatShape()
                        .trim(from: 0, to: ecgProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan, Color.white],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 74, height: 50)
                        .shadow(color: Color.cyan.opacity(ecgGlow), radius: 8, x: 0, y: 0)
                        .shadow(color: Color.white.opacity(ecgGlow * 0.7), radius: 4, x: 0, y: 0)
                }
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
                
                // Typography & Telemetry Status
                VStack(spacing: 8) {
                    Text("P U L S E")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.75, green: 0.92, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.4), radius: 12, x: 0, y: 2)
                    
                    Text("INFRASTRUCTURE TELEMETRY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color.cyan.opacity(0.85))
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.green, radius: 4)
                        
                        Text("SYSTEM READY")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                .offset(y: textOffset)
                .opacity(textOpacity)
            }
            .scaleEffect(dismissScale)
            .opacity(dismissOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissImmediately()
        }
        .onAppear {
            runAnimationSequence()
        }
    }
    
    private func runAnimationSequence() {
        // 1. Badge Spring In
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            badgeScale = 1.0
            badgeOpacity = 1.0
        }
        
        // 2. Concentric Radar Rings Expand
        withAnimation(.easeOut(duration: 0.9)) {
            ring1Scale = 1.85
            ring1Opacity = 0.0
        }
        withAnimation(.easeOut(duration: 1.1).delay(0.12)) {
            ring2Scale = 2.1
            ring2Opacity = 0.0
        }
        
        // 3. Draw ECG Waveform
        withAnimation(.easeInOut(duration: 0.65).delay(0.15)) {
            ecgProgress = 1.0
            ecgGlow = 0.9
        }
        
        // 4. Reveal Typography
        withAnimation(.easeOut(duration: 0.45).delay(0.35)) {
            textOffset = 0
            textOpacity = 1.0
        }
        
        // 5. Smooth Dismissal after completion (~1.25s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeInOut(duration: 0.35)) {
                dismissScale = 1.06
                dismissOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                isPresented = false
            }
        }
    }
    
    private func dismissImmediately() {
        withAnimation(.easeOut(duration: 0.2)) {
            dismissOpacity = 0.0
            dismissScale = 1.04
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
