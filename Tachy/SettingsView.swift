import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var dictationManager: DictationManager
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var savedMessage: String? = nil
    @State private var launchAtLogin: Bool = false

    private let settings = SettingsManager.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("Geral", systemImage: "gear")
                }

            apiKeysTab
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            aboutTab
                .tabItem {
                    Label("Sobre", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            openAIKey = settings.openAIKey
            anthropicKey = settings.anthropicKey
            launchAtLogin = settings.launchAtLogin
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Comportamento") {
                Picker("Nível de refinamento:", selection: $dictationManager.refinementLevel) {
                    ForEach(RefinementLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }

                Toggle("Transcrição ao vivo (Realtime API)", isOn: $dictationManager.useLiveTranscription)
                Toggle("Colar automaticamente no campo ativo", isOn: $dictationManager.autoPaste)
                Toggle("Mostrar notificações", isOn: $dictationManager.showNotifications)
            }

            Section("Atalho") {
                HStack {
                    Text("Gravar/Parar:")
                    Spacer()
                    Text("2x ⌃ (double-tap Control)")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            Section("Sistema") {
                Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
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

            Section {
                Button("Salvar") {
                    dictationManager.saveSettings()
                    savedMessage = "Configurações salvas!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedMessage = nil
                    }
                }

                if let msg = savedMessage {
                    Text(msg)
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding()
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section("OpenAI (Whisper + Realtime)") {
                HStack {
                    if showOpenAIKey {
                        TextField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                Text("Usada para transcrição de voz (Whisper API e Realtime API)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Anthropic (Claude)") {
                HStack {
                    if showAnthropicKey {
                        TextField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showAnthropicKey.toggle() }) {
                        Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                Text("Usada para refinamento de texto via Claude API")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Salvar API Keys") {
                    settings.openAIKey = openAIKey
                    settings.anthropicKey = anthropicKey
                    savedMessage = "API Keys salvas no Keychain!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedMessage = nil
                    }
                }
                .buttonStyle(.borderedProminent)

                if let msg = savedMessage {
                    Text(msg)
                        .foregroundColor(.green)
                        .font(.caption)
                }

                Text("As chaves são armazenadas com segurança no macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Tachy")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Ditado inteligente com transcrição ao vivo e refinamento por IA")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Transcrição ao vivo via OpenAI Realtime API", systemImage: "waveform")
                Label("Whisper API como fallback batch", systemImage: "arrow.triangle.2.circlepath")
                Label("Claude API para refinamento inteligente", systemImage: "sparkles")
                Label("Cola automática no campo ativo", systemImage: "doc.on.clipboard")
                Label("Double-tap ⌃ para gravar/parar", systemImage: "keyboard")
            }
            .font(.caption)

            Spacer()
        }
        .padding()
    }
}
