import SwiftUI
import ServiceManagement

// MARK: - Settings Navigation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, apiKeys, history, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "Geral"
        case .apiKeys: return "API Keys"
        case .history: return "Histórico"
        case .about: return "Sobre"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .apiKeys: return "key.fill"
        case .history: return "clock.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @State private var selectedTab: SettingsTab = .general
    @State private var openAIKey: String = ""
    @State private var showOpenAIKey: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var showSaved = false
    @Namespace private var sidebarNS

    private let settings = SettingsManager.shared

    private let accent = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.28), Color(red: 0.92, green: 0.28, blue: 0.44)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.15)
            contentArea
        }
        .frame(minWidth: 680, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openAIKey = settings.openAIKey
            launchAtLogin = settings.launchAtLogin
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Tachy")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Preferências")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("v1.0.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.25))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 180)
        .background(Color.primary.opacity(0.015))
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)

                Text(tab.label)
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))

                Spacer()

                if tab == .history && !dictationManager.history.isEmpty {
                    Text("\(dictationManager.history.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            selectedTab == tab
                                ? Color.white.opacity(0.18)
                                : Color.primary.opacity(0.06)
                        )
                        .cornerRadius(4)
                }
            }
            .foregroundColor(selectedTab == tab ? .white : .primary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                Group {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(accent.opacity(0.9))
                            .matchedGeometryEffect(id: "sel", in: sidebarNS)
                            .shadow(color: Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.2), radius: 8, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedTab.label)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if showSaved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Salvo")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general: generalContent
                    case .apiKeys: apiKeysContent
                    case .history: historyContent
                    case .about: aboutContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(spacing: 16) {
            card("Comportamento") {
                VStack(spacing: 12) {
                    toggleRow("Transcrição ao vivo", sub: "Usa OpenAI Realtime API", icon: "waveform", isOn: $dictationManager.useLiveTranscription)
                    Divider().opacity(0.12)
                    toggleRow("Colar automaticamente", sub: "Cola no campo ativo ao finalizar", icon: "doc.on.clipboard", isOn: $dictationManager.autoPaste)
                    Divider().opacity(0.12)
                    toggleRow("Notificações", sub: "Exibe resultado como notificação", icon: "bell", isOn: $dictationManager.showNotifications)
                }
            }

            card("Atalhos") {
                VStack(spacing: 10) {
                    shortcutRow(label: "Gravar / Parar", keys: "2x ⌃", hint: "Double-tap Control")
                    Divider().opacity(0.12)
                    shortcutRow(label: "Pausar / Retomar", keys: "2x ⇧", hint: "Double-tap Shift")
                    Divider().opacity(0.12)
                    shortcutRow(label: "Fechar resultado", keys: "⎋", hint: "Escape")
                }
            }

            card("Sistema") {
                toggleRow("Abrir ao iniciar sessão", sub: "Inicia o Tachy com o macOS", icon: "power", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        settings.launchAtLogin = newValue
                        if #available(macOS 13.0, *) {
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Launch at login error: \(error)")
                            }
                        }
                    }
            }

            saveButton("Salvar configurações") {
                dictationManager.saveSettings()
                flashSaved()
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysContent: some View {
        VStack(spacing: 16) {
            card("OpenAI") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHAVE DE API")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.45))
                        .tracking(0.6)

                    HStack(spacing: 8) {
                        Group {
                            if showOpenAIKey {
                                TextField("sk-...", text: $openAIKey)
                            } else {
                                SecureField("sk-...", text: $openAIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                        Button(action: { showOpenAIKey.toggle() }) {
                            Image(systemName: showOpenAIKey ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                        Text("Armazenada com segurança no macOS Keychain")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary.opacity(0.4))
                }
            }

            card("Uso da chave") {
                VStack(spacing: 8) {
                    usageRow(icon: "waveform", label: "Whisper", detail: "Transcrição batch")
                    Divider().opacity(0.12)
                    usageRow(icon: "antenna.radiowaves.left.and.right", label: "Realtime API", detail: "Transcrição ao vivo")
                }
            }

            saveButton("Salvar API Key") {
                settings.openAIKey = openAIKey
                flashSaved()
            }
        }
    }

    // MARK: - History

    private var historyContent: some View {
        VStack(spacing: 0) {
            if dictationManager.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary.opacity(0.18))
                    Text("Nenhuma transcrição ainda")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("Faça sua primeira ditação com 2x ⌃")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dictationManager.history) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(accent)

                VStack(spacing: 4) {
                    Text("Tachy")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("v1.0.0")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }

                Text("Ditado por voz com transcrição ao vivo e limpeza inteligente")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            card("Recursos") {
                VStack(alignment: .leading, spacing: 8) {
                    featureRow(icon: "waveform", color: .orange, text: "Transcrição ao vivo via Realtime API")
                    featureRow(icon: "arrow.triangle.2.circlepath", color: .blue, text: "Whisper API como fallback batch")
                    featureRow(icon: "sparkles", color: .purple, text: "Limpeza automática de vícios de fala")
                    featureRow(icon: "doc.on.clipboard", color: .green, text: "Cola automática no campo ativo")
                    featureRow(icon: "keyboard", color: .secondary, text: "Double-tap ⌃ para gravar/parar")
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.4))
                .tracking(0.8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
    }

    private func toggleRow(_ title: String, sub: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.45))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.45))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
    }

    private func shortcutRow(label: String, keys: String, hint: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))

            Spacer()

            HStack(spacing: 6) {
                Text(keys)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.35))
            }
        }
    }

    private func usageRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.45))
                .frame(width: 18)

            Text(label)
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.35))
        }
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color.opacity(0.65))
                .frame(width: 18)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.7))
        }
    }

    private func saveButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(accent.opacity(0.85))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func flashSaved() {
        withAnimation(.easeInOut(duration: 0.2)) { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) { showSaved = false }
        }
    }
}
