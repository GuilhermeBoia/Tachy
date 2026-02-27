import SwiftUI

// MARK: - Navigation

enum TachyPage {
    case main
    case history
    case settings
}

// MARK: - Root Panel View

struct TachyPanelView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @State private var currentPage: TachyPage = .main

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            Group {
                switch currentPage {
                case .main:
                    TachyMainView(currentPage: $currentPage)
                case .history:
                    TachyHistoryView(currentPage: $currentPage)
                case .settings:
                    TachySettingsView(currentPage: $currentPage)
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
        .environmentObject(dictationManager)
    }
}

// MARK: - Main View

struct TachyMainView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @Binding var currentPage: TachyPage
    @State private var lastResultCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.3)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Record button
                    recordButton

                    // Live area / Status
                    if isActiveRecording {
                        liveArea
                    } else if dictationManager.state == .transcribing || dictationManager.state == .refining {
                        processingStatus
                    }

                    // Last result
                    if !dictationManager.lastRefined.isEmpty && !isActiveRecording && dictationManager.state == .idle {
                        lastResult
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.3)

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    isActiveRecording
                        ? LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Tachy")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            // Refinement picker inline
            Picker("", selection: $dictationManager.refinementLevel) {
                ForEach(RefinementLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .scaleEffect(0.85, anchor: .leading)

            Spacer()

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .fill(statusColor.opacity(0.4))
                        .frame(width: 12, height: 12)
                        .opacity(isActiveRecording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActiveRecording)
                )

            Text(statusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: { dictationManager.toggleRecording() }) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 14, weight: .semibold))
                Text(buttonLabel)
                    .font(.system(size: 13, weight: .semibold))
                if isActiveRecording {
                    Spacer()
                    Text(formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isActiveRecording
                    ? AnyShapeStyle(LinearGradient(colors: [Color.red, Color.red.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
            )
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(dictationManager.state == .transcribing || dictationManager.state == .refining)
    }

    // MARK: - Live Area

    private var liveArea: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Live text — scrollable, no line limit
            if !dictationManager.livePartialText.isEmpty {
                Text(dictationManager.livePartialText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Processing Status

    private var processingStatus: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Last Result

    private var lastResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Último resultado")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dictationManager.lastRefined, forType: .string)
                    lastResultCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { lastResultCopied = false }
                }) {
                    Image(systemName: lastResultCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(lastResultCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(dictationManager.lastRefined)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("2x ⌃")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)

            Spacer()

            HStack(spacing: 16) {
                Button("Histórico") {
                    withAnimation(.easeInOut(duration: 0.15)) { currentPage = .history }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Ajustes") {
                    withAnimation(.easeInOut(duration: 0.15)) { currentPage = .settings }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Sair") {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.6))
            }
        }
    }

    // MARK: - Helpers

    private var isActiveRecording: Bool {
        dictationManager.state == .recording || dictationManager.state == .liveTranscribing
    }

    private var formattedDuration: String {
        let minutes = Int(dictationManager.recordingDuration) / 60
        let seconds = Int(dictationManager.recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var statusColor: Color {
        switch dictationManager.state {
        case .idle: return .green
        case .recording, .liveTranscribing: return .red
        case .transcribing: return .orange
        case .refining: return .purple
        }
    }

    private var statusLabel: String {
        switch dictationManager.state {
        case .idle: return "Pronto"
        case .recording: return "Gravando"
        case .liveTranscribing: return "Ao Vivo"
        case .transcribing: return "Transcrevendo"
        case .refining: return "Refinando"
        }
    }

    private var buttonIcon: String {
        switch dictationManager.state {
        case .idle: return "mic.fill"
        case .recording, .liveTranscribing: return "stop.fill"
        case .transcribing: return "waveform"
        case .refining: return "sparkles"
        }
    }

    private var buttonLabel: String {
        switch dictationManager.state {
        case .idle: return "Iniciar Gravação"
        case .recording, .liveTranscribing: return "Parar"
        case .transcribing: return "Transcrevendo..."
        case .refining: return "Refinando..."
        }
    }

    private var statusText: String {
        switch dictationManager.state {
        case .transcribing: return "Transcrevendo com Whisper..."
        case .refining: return "Refinando com GPT..."
        default: return ""
        }
    }
}

// MARK: - History View

struct TachyHistoryView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @Binding var currentPage: TachyPage

    var body: some View {
        VStack(spacing: 0) {
            // Header with back
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { currentPage = .main } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("Histórico")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

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

    /// Relative time without seconds — "agora", "2 min", "1 h", "3 dias"
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

// MARK: - Settings View (Inline)

struct TachySettingsView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @Binding var currentPage: TachyPage
    @State private var openAIKey: String = ""
    @State private var showOpenAIKey = false
    @State private var launchAtLogin = false
    @State private var savedMessage: String? = nil

    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with back
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { currentPage = .main } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("Ajustes")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Behavior
                    settingsSection("Comportamento") {
                        settingsRow {
                            Toggle("Transcrição ao vivo", isOn: $dictationManager.useLiveTranscription)
                                .font(.system(size: 12))
                        }
                        settingsRow {
                            Toggle("Colar no campo ativo", isOn: $dictationManager.autoPaste)
                                .font(.system(size: 12))
                        }
                        settingsRow {
                            Toggle("Notificações", isOn: $dictationManager.showNotifications)
                                .font(.system(size: 12))
                        }
                    }

                    // API Keys
                    settingsSection("API Keys") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenAI (Whisper + Realtime + GPT)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                if showOpenAIKey {
                                    TextField("sk-...", text: $openAIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                } else {
                                    SecureField("sk-...", text: $openAIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                }
                                Button { showOpenAIKey.toggle() } label: {
                                    Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Shortcut info
                    settingsSection("Atalho") {
                        HStack {
                            Text("Gravar / Parar")
                                .font(.system(size: 12))
                            Spacer()
                            Text("2x ⌃")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(5)
                        }
                    }

                    // Save
                    Button(action: saveAll) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text(savedMessage ?? "Salvar tudo")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            savedMessage != nil
                                ? AnyShapeStyle(Color.green.opacity(0.2))
                                : AnyShapeStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundColor(savedMessage != nil ? .green : .white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .onAppear {
            openAIKey = settings.openAIKey
            launchAtLogin = settings.launchAtLogin
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(0.5)

            VStack(spacing: 6) {
                content()
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
    }

    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    private func saveAll() {
        settings.openAIKey = openAIKey
        dictationManager.saveSettings()
        savedMessage = "Salvo!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedMessage = nil }
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
