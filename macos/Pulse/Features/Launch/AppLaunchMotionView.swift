import SwiftUI

/// Animated ECG / Heartbeat waveform path
struct HeartbeatECGPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let mid = h * 0.52
        
        path.move(to: CGPoint(x: 0, y: mid))
        // Baseline leading
        path.addLine(to: CGPoint(x: w * 0.20, y: mid))
        // P-wave (smooth gentle atrial bump)
        path.addCurve(
            to: CGPoint(x: w * 0.32, y: mid),
            control1: CGPoint(x: w * 0.24, y: mid - h * 0.16),
            control2: CGPoint(x: w * 0.28, y: mid - h * 0.16)
        )
        // Baseline segment
        path.addLine(to: CGPoint(x: w * 0.38, y: mid))
        // Q-dip (sharp slight dip)
        path.addLine(to: CGPoint(x: w * 0.42, y: mid + h * 0.14))
        // R-spike (crisp vertical cardiac spike)
        path.addLine(to: CGPoint(x: w * 0.48, y: mid - h * 0.50))
        // S-valley (deep sharp valley)
        path.addLine(to: CGPoint(x: w * 0.54, y: mid + h * 0.34))
        // Return to baseline
        path.addLine(to: CGPoint(x: w * 0.58, y: mid))
        // T-wave (smooth recovery dome)
        path.addCurve(
            to: CGPoint(x: w * 0.76, y: mid),
            control1: CGPoint(x: w * 0.63, y: mid - h * 0.26),
            control2: CGPoint(x: w * 0.71, y: mid - h * 0.26)
        )
        // Baseline trailing
        path.addLine(to: CGPoint(x: w, y: mid))
        
        return path
    }
}

/// Feature tour step model
struct TourStep: Identifiable {
    let id: Int
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let details: [(icon: String, text: String)]
}

public struct AppLaunchMotionView: View {
    @Binding var isPresented: Bool
    var onAddServerRequested: (() -> Void)? = nil
    
    @ObservedObject private var settings = AppSettingsStore.shared
    
    // Logo Motion States
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 0.0
    @State private var ecgProgress: CGFloat = 0.0
    @State private var ecgGlow: Double = 0.0
    @State private var cardiacPulseScale: CGFloat = 1.0
    
    // Sonar Radar Rings
    @State private var ring1Scale: CGFloat = 0.9
    @State private var ring1Opacity: Double = 0.7
    @State private var ring2Scale: CGFloat = 0.9
    @State private var ring2Opacity: Double = 0.5
    
    // Transition to Guide State
    @State private var showWelcomeGuide: Bool = false
    @State private var currentStep: Int = 0
    @State private var guideOpacity: Double = 0.0
    @State private var guideScale: CGFloat = 0.95
    @State private var logoYOffset: CGFloat = 0
    
    // Master View Dismissal State
    @State private var masterScale: CGFloat = 1.0
    @State private var masterOpacity: Double = 1.0
    
    private let tourSteps: [TourStep] = [
        TourStep(
            id: 0,
            icon: "chart.xyaxis.line",
            iconColor: .teal,
            title: "Real-Time Telemetry & Probes",
            subtitle: "Instant sub-second observability for Linux & macOS nodes.",
            details: [
                ("bolt.fill", "Sub-second streaming CPU, RAM, Disk I/O & Network rates"),
                ("shippingbox.fill", "Live Docker container inspector & 1-click log streaming"),
                ("gauge.with.needle.fill", "Automated anomaly detection & historical trend analysis")
            ]
        ),
        TourStep(
            id: 1,
            icon: "lock.shield.fill",
            iconColor: .blue,
            title: "Zero-Inbound Private Networks",
            subtitle: "No exposed firewall ports required. Air-gapped security by design.",
            details: [
                ("key.fill", "Mutual TLS (mTLS) with SHA-256 certificate fingerprint pinning"),
                ("network.badge.shield.half.filled", "Seamless Tailscale WireGuard mesh (100.64.0.0/10) integration"),
                ("cloud.fill", "Cloudflare Zero-Trust Tunnel support with zero inbound ports")
            ]
        ),
        TourStep(
            id: 2,
            icon: "shield.lefthalf.filled",
            iconColor: .purple,
            title: "Network & Open Ports Auditor",
            subtitle: "Live socket inspector auditing security exposure in real time.",
            details: [
                ("dot.radiowaves.left.and.right", "Continuous live TCP/UDP socket scanner (Linux ss & macOS lsof)"),
                ("exclamationmark.triangle.fill", "Instant alerts when Redis, Postgres, or MySQL listen on 0.0.0.0"),
                ("flame.fill", "Host firewall auditor inspecting UFW, iptables, and pf policies")
            ]
        ),
        TourStep(
            id: 3,
            icon: "bolt.badge.automatic.fill",
            iconColor: .orange,
            title: "Smart Remediation & Deep Integration",
            subtitle: "Fast recovery from incidents and native macOS system presence.",
            details: [
                ("arrow.triangle.merge", "Deterministic root-cause analysis separating causes from symptoms"),
                ("menubar.rectangle", "Always-available Menu Bar extra for cluster glances without opening windows"),
                ("link", "1-Click server onboarding via custom pulse:// URL scheme")
            ]
        )
    ]
    
    public init(isPresented: Binding<Bool>, onAddServerRequested: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.onAddServerRequested = onAddServerRequested
    }
    
    public var body: some View {
        ZStack {
            // Deep Cinematic Dark Canvas
            Color(red: 0.03, green: 0.04, blue: 0.06)
                .ignoresSafeArea()
            
            // Soft Radial Atmosphere Glow
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.12),
                    Color.blue.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 360
            )
            .ignoresSafeArea()
            
            if !showWelcomeGuide {
                // ==========================================
                // PHASE 1: Pure Animated Pulse Logo (NO TEXT)
                // ==========================================
                ZStack {
                    // Expanding Sonar Ring 1
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.55), Color.blue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(ring1Scale)
                        .opacity(ring1Opacity)
                    
                    // Expanding Sonar Ring 2
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                        .frame(width: 170, height: 170)
                        .scaleEffect(ring2Scale)
                        .opacity(ring2Opacity)
                    
                    // Pulse Logo Squircle Container
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.14, blue: 0.22),
                                    Color(red: 0.05, green: 0.07, blue: 0.11)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 114, height: 114)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.cyan.opacity(0.75),
                                            Color.blue.opacity(0.3),
                                            Color.teal.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.4
                                )
                        )
                        .shadow(color: Color.cyan.opacity(ecgGlow * 0.4), radius: 28, x: 0, y: 6)
                        .shadow(color: Color.blue.opacity(ecgGlow * 0.3), radius: 40, x: 0, y: 12)
                    
                    // Animated Neon ECG Line
                    ZStack {
                        // Background soft blur for neon bloom
                        HeartbeatECGPath()
                            .trim(from: 0, to: ecgProgress)
                            .stroke(
                                Color.cyan.opacity(0.7),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 4)
                            .frame(width: 82, height: 56)
                        
                        // Sharp Foreground Neon ECG Line
                        HeartbeatECGPath()
                            .trim(from: 0, to: ecgProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.2, green: 0.6, blue: 1.0),
                                        Color.cyan,
                                        Color.white,
                                        Color.teal
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 82, height: 56)
                            .shadow(color: Color.white.opacity(ecgGlow * 0.8), radius: 3, x: 0, y: 0)
                    }
                }
                .scaleEffect(logoScale * cardiacPulseScale)
                .opacity(logoOpacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTapToSkip()
                }
            } else {
                // ==========================================
                // PHASE 2: First-Time Welcome & Feature Guide
                // ==========================================
                welcomeGuideContent
                    .opacity(guideOpacity)
                    .scaleEffect(guideScale)
            }
        }
        .scaleEffect(masterScale)
        .opacity(masterOpacity)
        .onAppear {
            runCinematicLogoAnimation()
        }
    }
    
    // MARK: - Welcome Guide Content
    private var welcomeGuideContent: some View {
        VStack(spacing: 24) {
            // Top Bar: Mini Logo + Skip Button
            HStack {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.8), Color.blue.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to Pulse")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Interactive Feature Tour")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Skip Tour") {
                    finishWelcomeGuide(openAddServer: false)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            
            // Central Card Deck
            TabView(selection: $currentStep) {
                ForEach(tourSteps) { step in
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(step.iconColor.opacity(0.18))
                                    .frame(width: 52, height: 52)
                                
                                Image(systemName: step.icon)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(step.iconColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text(step.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(step.details, id: \.text) { detail in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: detail.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(step.iconColor)
                                        .frame(width: 18, height: 18)
                                    
                                    Text(detail.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(nsColor: .labelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                    .tag(step.id)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 290)
            
            // Bottom Bar: Dots & Navigation Buttons
            HStack {
                // Page Indicator Dots
                HStack(spacing: 6) {
                    ForEach(0..<tourSteps.count, id: \.self) { idx in
                        Circle()
                            .fill(currentStep == idx ? Color.cyan : Color.white.opacity(0.2))
                            .frame(width: currentStep == idx ? 8 : 6, height: currentStep == idx ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentStep)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Previous") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentStep -= 1
                            }
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    }
                    
                    if currentStep < tourSteps.count - 1 {
                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    } else {
                        Button("Get Started & Add Server") {
                            finishWelcomeGuide(openAddServer: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 580, height: 440)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.06, green: 0.07, blue: 0.11))
                .shadow(color: Color.black.opacity(0.6), radius: 36, x: 0, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Animation Orchestration
    private func runCinematicLogoAnimation() {
        // Step 1: Smooth, calm logo fade-in and scale with damping
        withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Step 2: Expanding soft radar pulse rings
        withAnimation(.easeOut(duration: 1.4).delay(0.2)) {
            ring1Scale = 1.95
            ring1Opacity = 0.0
        }
        withAnimation(.easeOut(duration: 1.6).delay(0.4)) {
            ring2Scale = 2.2
            ring2Opacity = 0.0
        }
        
        // Step 3: Draw the neon ECG heartbeat wave with calm cinematic pacing
        withAnimation(.easeInOut(duration: 0.95).delay(0.35)) {
            ecgProgress = 1.0
            ecgGlow = 1.0
        }
        
        // Step 4: Gentle cardiac heartbeat pulse bloom
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                cardiacPulseScale = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    cardiacPulseScale = 1.0
                }
            }
        }
        
        // Step 5: Post-animation routing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !settings.hasCompletedWelcomeGuide {
                // First time launch: Transition into Welcome Guide
                withAnimation(.easeInOut(duration: 0.55)) {
                    showWelcomeGuide = true
                    guideOpacity = 1.0
                    guideScale = 1.0
                }
            } else {
                // Subsequent launch: Smoothly dissolve out to main window
                withAnimation(.easeInOut(duration: 0.45)) {
                    masterScale = 1.03
                    masterOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                    isPresented = false
                }
            }
        }
    }
    
    private func handleTapToSkip() {
        if !settings.hasCompletedWelcomeGuide {
            withAnimation(.easeInOut(duration: 0.35)) {
                showWelcomeGuide = true
                guideOpacity = 1.0
                guideScale = 1.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                masterOpacity = 0.0
                masterScale = 1.02
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPresented = false
            }
        }
    }
    
    private func finishWelcomeGuide(openAddServer: Bool) {
        settings.hasCompletedWelcomeGuide = true
        withAnimation(.easeInOut(duration: 0.35)) {
            masterOpacity = 0.0
            masterScale = 1.02
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            isPresented = false
            if openAddServer {
                onAddServerRequested?()
            }
        }
    }
}
