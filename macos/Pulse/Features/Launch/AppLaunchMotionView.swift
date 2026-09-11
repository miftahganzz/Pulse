import SwiftUI

// MARK: - Tour Step Data

struct TourStep: Identifiable {
    let id: Int
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let bullets: [(icon: String, text: String)]
}

// MARK: - Main Launch / Onboarding View

public struct AppLaunchMotionView: View {
    @Binding var isPresented: Bool
    var onAddServerRequested: (() -> Void)? = nil

    @ObservedObject private var settings = AppSettingsStore.shared

    // Logo splash states
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.88
    @State private var contentOpacity: Double = 0

    // Welcome guide
    @State private var showGuide: Bool = false
    @State private var currentStep: Int = 0

    // Dismissal
    @State private var rootOpacity: Double = 1

    private let steps: [TourStep] = [
        TourStep(
            id: 0,
            icon: "chart.xyaxis.line",
            iconColor: .blue,
            title: "Real-Time Infrastructure Telemetry",
            description: "Monitor every node, container, and service with sub-second precision.",
            bullets: [
                ("bolt", "Sub-second CPU, RAM, Disk I/O & Network streaming"),
                ("shippingbox", "Docker container inspector with live log streaming"),
                ("waveform.path.ecg", "Anomaly detection and historical trend analysis")
            ]
        ),
        TourStep(
            id: 1,
            icon: "lock.shield",
            iconColor: .blue,
            title: "Zero Inbound Exposure",
            description: "Connect securely without opening a single firewall port.",
            bullets: [
                ("key", "Mutual TLS with SHA-256 certificate fingerprint pinning"),
                ("personalhotspot", "Tailscale WireGuard mesh — no public IP required"),
                ("cloud", "Cloudflare Tunnel with zero open inbound ports")
            ]
        ),
        TourStep(
            id: 2,
            icon: "shield.lefthalf.filled",
            iconColor: .blue,
            title: "Network & Ports Auditor",
            description: "Inspect every open socket and audit your firewall in real time.",
            bullets: [
                ("dot.radiowaves.left.and.right", "Live TCP/UDP scanner via ss and lsof"),
                ("exclamationmark.triangle", "Alerts when databases listen on 0.0.0.0"),
                ("checklist", "Firewall policy auditor for UFW, iptables, pf")
            ]
        ),
        TourStep(
            id: 3,
            icon: "menubar.rectangle",
            iconColor: .blue,
            title: "Always-On macOS Integration",
            description: "Native macOS presence so you're never out of the loop.",
            bullets: [
                ("menubar.rectangle", "Menu Bar extra with live incident count badge"),
                ("link", "1-Click onboarding via pulse:// deep links"),
                ("arrow.triangle.2.circlepath", "Auto-reconnect after sleep, wake, and network changes")
            ]
        )
    ]

    public init(isPresented: Binding<Bool>, onAddServerRequested: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.onAddServerRequested = onAddServerRequested
    }

    public var body: some View {
        Group {
            if showGuide {
                WelcomeGuideView(
                    steps: steps,
                    onDone: { addServer in
                        finishGuide(addServer: addServer)
                    },
                    onSkip: {
                        finishGuide(addServer: false)
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))
            } else {
                // Logo Splash
                splashView
                    .transition(.opacity)
            }
        }
        .opacity(rootOpacity)
        .onAppear { runSplash() }
    }

    // MARK: - Splash

    private var splashView: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(nsColor: .windowBackgroundColor)
                .opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // App icon — clean squircle, no neon, no rings
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 96, height: 96)
                        .shadow(color: Color.accentColor.opacity(0.25), radius: 20, x: 0, y: 8)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                VStack(spacing: 6) {
                    Text("Pulse")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Infrastructure Monitoring")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .opacity(contentOpacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToGuide() }
    }

    // MARK: - Animation

    private func runSplash() {
        // Icon fades in
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
            logoOpacity = 1
            logoScale = 1
        }
        // Name/subtitle slides up
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            contentOpacity = 1
        }
        // Route after splash
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if !settings.hasCompletedWelcomeGuide {
                skipToGuide()
            } else {
                dismiss()
            }
        }
    }

    private func skipToGuide() {
        guard !showGuide else { return }
        if !settings.hasCompletedWelcomeGuide {
            withAnimation(.easeInOut(duration: 0.3)) { showGuide = true }
        } else {
            dismiss()
        }
    }

    private func finishGuide(addServer: Bool) {
        settings.hasCompletedWelcomeGuide = true
        withAnimation(.easeOut(duration: 0.25)) { rootOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            isPresented = false
            if addServer { onAddServerRequested?() }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) { rootOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) { isPresented = false }
    }
}

// MARK: - Welcome Guide

private struct WelcomeGuideView: View {
    let steps: [TourStep]
    let onDone: (Bool) -> Void
    let onSkip: () -> Void

    @State private var currentStep: Int = 0
    @State private var stepDirection: Int = 1  // +1 forward, -1 backward

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────────
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to Pulse")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Quick tour — \(steps.count) steps")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Skip") { onSkip() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)

                Divider()

                // ── Step content ─────────────────────────────────────────
                stepContent
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                // ── Footer ───────────────────────────────────────────────
                HStack {
                    // Dot indicators
                    HStack(spacing: 5) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentStep
                                      ? Color.accentColor
                                      : Color.secondary.opacity(0.25))
                                .frame(width: i == currentStep ? 20 : 7, height: 7)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStep)
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if currentStep > 0 {
                            Button("Back") { navigate(by: -1) }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                        }

                        if currentStep < steps.count - 1 {
                            Button("Continue") { navigate(by: 1) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Get Started") { onDone(true) }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(width: 540, height: 420)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        let step = steps[currentStep]

        VStack(alignment: .leading, spacing: 20) {
            // Icon + Title + Description row
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: step.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(step.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Bullet points
            VStack(alignment: .leading, spacing: 14) {
                ForEach(step.bullets, id: \.text) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: bullet.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 18)

                        Text(bullet.text)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .id(currentStep)                                // re-render on step change
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: stepDirection > 0 ? .trailing : .leading)),
            removal:   .opacity.combined(with: .move(edge: stepDirection > 0 ? .leading  : .trailing))
        ))
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    private func navigate(by delta: Int) {
        stepDirection = delta
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep += delta
        }
    }
}

// MARK: - Vibrancy helper

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
