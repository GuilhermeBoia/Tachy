import SwiftUI

// MARK: - Root Panel View (State Router)

struct TachyPanelView: View {
    @EnvironmentObject var dictationManager: DictationManager

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            Group {
                switch dictationManager.state {
                case .recording, .liveTranscribing, .paused:
                    CompactRecordingPill()
                case .transcribing:
                    ProcessingIndicator()
                case .idle:
                    if dictationManager.showingResult {
                        ResultDisplayView()
                    } else {
                        Color.clear
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: dictationManager.state)
            .animation(.easeInOut(duration: 0.2), value: dictationManager.showingResult)
        }
        .environmentObject(dictationManager)
    }
}

// MARK: - Compact Recording Pill (300x50)

struct CompactRecordingPill: View {
    @EnvironmentObject var dictationManager: DictationManager

    var body: some View {
        HStack(spacing: 12) {
            // Duration
            Text(formattedDuration)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 48, alignment: .leading)

            // Waveform
            AudioWaveformView(
                audioLevel: dictationManager.audioLevel,
                isPaused: dictationManager.state == .paused
            )

            // Pause/Play button
            Button(action: { dictationManager.togglePause() }) {
                Image(systemName: dictationManager.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Stop button
            Button(action: { dictationManager.toggleRecording() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formattedDuration: String {
        let total = Int(dictationManager.recordingDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let audioLevel: Float
    let isPaused: Bool

    private let barCount = 30
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 24
    private let minBarHeight: CGFloat = 2

    @State private var levels: [Float] = Array(repeating: 0, count: 30)
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.7))
                    .frame(
                        width: barWidth,
                        height: barHeight(for: levels[index])
                    )
                    .animation(.linear(duration: 0.05), value: levels[index])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startSampling() }
        .onDisappear { stopSampling() }
        .onChange(of: isPaused) { paused in
            if paused {
                stopSampling()
            } else {
                startSampling()
            }
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let normalized = CGFloat(max(0, min(1, level)))
        return minBarHeight + normalized * (maxBarHeight - minBarHeight)
    }

    private func startSampling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                // Shift left, push new sample
                var newLevels = levels
                newLevels.removeFirst()
                // Add some randomness to make it look natural
                let base = audioLevel
                let jitter = Float.random(in: -0.05...0.05)
                newLevels.append(max(0, min(1, base + jitter)))
                levels = newLevels
            }
        }
    }

    private func stopSampling() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Processing Indicator (300x50)

struct ProcessingIndicator: View {
    @EnvironmentObject var dictationManager: DictationManager

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        switch dictationManager.state {
        case .transcribing: return "Transcrevendo..."
        default: return "Processando..."
        }
    }
}

// MARK: - Result Display View (380 x dynamic)

struct ResultDisplayView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @State private var showCopiedBadge = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top bar
            HStack {
                if showCopiedBadge {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Copiado")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()

                Button(action: { dictationManager.dismissResult() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Result text
            ScrollView {
                Text(dictationManager.lastResult)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ResultHeightKey.self, value: geo.size.height)
                        }
                    )
            }
            .frame(maxHeight: 280)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onPreferenceChange(ResultHeightKey.self) { height in
            // Total height = text height + top bar (~20) + padding (24) + scroll chrome
            let totalHeight = height + 60
            NotificationCenter.default.post(
                name: Notification.Name("TachyResultHeightChanged"),
                object: nil,
                userInfo: ["height": totalHeight]
            )
        }
        .onAppear {
            showCopiedBadge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCopiedBadge = false
                }
            }
        }
    }
}

private struct ResultHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - History View (Standalone Window)

struct TachyHistoryView: View {
    @EnvironmentObject var dictationManager: DictationManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Histórico")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Spacer()

                Text("\(dictationManager.history.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            if dictationManager.history.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Nenhuma entrada ainda")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(dictationManager.history) { entry in
                            HistoryRow(entry: entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: DictationEntry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(relativeTime(entry.date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.refined, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            Text(entry.refined)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.original != entry.refined {
                Text(entry.original)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "agora" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return "\(days) dia\(days > 1 ? "s" : "")"
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
