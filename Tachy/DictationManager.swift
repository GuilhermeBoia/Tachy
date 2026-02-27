import Foundation
import AVFoundation
import AppKit
import Combine
import UserNotifications

enum DictationState {
    case idle
    case recording
    case liveTranscribing
    case paused
    case transcribing
    case refining
}

enum RefinementLevel: String, CaseIterable, Codable {
    case none = "none"
    case refine = "refine"
    case prompt = "prompt"

    var displayName: String {
        switch self {
        case .none:
            return "Sem refinamento"
        case .refine:
            return "Refinamento"
        case .prompt:
            return "Prompt técnico"
        }
    }

    // Backward compatibility with old stored labels/cases.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let mapped = Self.fromStoredValue(value) {
            self = mapped
        } else {
            self = .refine
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func fromStoredValue(_ value: String) -> RefinementLevel? {
        switch value {
        case "none", "Sem refinamento":
            return RefinementLevel.none
        case "refine", "Refinamento", "Leve (pontuação e clareza)", "Moderado (reescrita leve)":
            return .refine
        case "prompt", "Prompt técnico":
            return .prompt
        default:
            return nil
        }
    }
}

class DictationManager: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var lastTranscription: String = ""
    @Published var lastRefined: String = ""
    @Published var isEnabled: Bool = true
    @Published var refinementLevel: RefinementLevel = .refine
    @Published var showNotifications: Bool = true
    @Published var autoPaste: Bool = true
    @Published var useLiveTranscription: Bool = true
    @Published var history: [DictationEntry] = []
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var livePartialText: String = ""
    @Published var showingResult: Bool = false

    var onStateChange: ((DictationState) -> Void)?

    private let audioRecorder = AudioRecorder()
    private let whisperService = WhisperService()
    private let refinementService = RefinementService()
    private let settingsManager = SettingsManager.shared
    private let realtimeService = RealtimeTranscriptionService()
    private let liveTextInserter = LiveTextInserter()

    private var recordingTimer: Timer?
    private var stateBeforePause: DictationState?

    init() {
        loadSettings()
        loadHistory()
        requestNotificationPermission()
        realtimeService.delegate = self
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Recording Control

    func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording, .liveTranscribing:
            stopRecording()
        case .paused:
            stopRecording()
        default:
            break
        }
    }

    func togglePause() {
        switch state {
        case .recording, .liveTranscribing:
            stateBeforePause = state
            audioRecorder.pauseRecording()
            recordingTimer?.invalidate()
            recordingTimer = nil
            audioLevel = 0
            setState(.paused)
            playSound(.start)
        case .paused:
            guard let previousState = stateBeforePause else { return }
            audioRecorder.resumeRecording()
            // Resume timer without resetting duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 1
            }
            setState(previousState)
            stateBeforePause = nil
            playSound(.start)
        default:
            break
        }
    }

    func dismissResult() {
        showingResult = false
        onStateChange?(state)
    }

    func cancelRecording() {
        guard state == .recording || state == .liveTranscribing || state == .paused else { return }

        let wasLive = state == .liveTranscribing || stateBeforePause == .liveTranscribing

        stopRecordingTimer()
        audioRecorder.cancelRecording()
        realtimeService.disconnect()

        if wasLive {
            liveTextInserter.deleteAllInserted()
        }

        livePartialText = ""
        audioLevel = 0
        stateBeforePause = nil
        setState(.idle)
        playSound(.error)
    }

    func startRecording() {
        guard state == .idle else { return }

        audioRecorder.onAudioLevel = { [weak self] level in
            self?.audioLevel = level
        }

        if useLiveTranscription {
            startLiveRecording()
        } else {
            startBatchRecording()
        }
    }

    private func startLiveRecording() {
        audioRecorder.onAudioData = { [weak self] data in
            self?.realtimeService.sendAudio(pcmData: data)
        }

        liveTextInserter.reset()
        livePartialText = ""

        // Connect WebSocket FIRST, then start recording only after connection is established.
        realtimeService.onConnected = { [weak self] in
            guard let self = self else { return }

            self.audioRecorder.startRecording { [weak self] success in
                guard let self = self else { return }
                guard success else {
                    self.realtimeService.disconnect()
                    self.showError("Não foi possível acessar o microfone. Verifique se outro app está usando.")
                    return
                }

                DispatchQueue.main.async {
                    self.setState(.liveTranscribing)
                    self.startRecordingTimer()
                    self.playSound(.start)
                }
            }
        }

        // Handle connection failure (timeout, auth error, network error)
        realtimeService.onConnectionFailed = { [weak self] error in
            guard let self = self else { return }
            NSLog("[Tachy] Connection failed: \(error.localizedDescription)")
            self.showError("Conexão falhou: \(error.localizedDescription)")
            self.setState(.idle)
        }

        realtimeService.connect()
    }

    private func startBatchRecording() {
        audioRecorder.startRecording { [weak self] success in
            guard success else {
                self?.showError("Não foi possível acessar o microfone. Verifique se outro app está usando.")
                return
            }
            DispatchQueue.main.async {
                self?.setState(.recording)
                self?.startRecordingTimer()
                self?.playSound(.start)
            }
        }
    }

    func stopRecording() {
        guard state == .recording || state == .liveTranscribing || state == .paused else { return }

        let wasLive = state == .liveTranscribing || stateBeforePause == .liveTranscribing
        stateBeforePause = nil

        if wasLive {
            // Keep mic open briefly so trailing silence reaches the API,
            // helping it detect end-of-speech and flush the final turn.
            stopRecordingTimer()
            setState(.transcribing)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }

                // Now stop the mic
                self.audioRecorder.stopRecording { [weak self] _ in
                    guard let self = self else { return }

                    // Wait for the API to send back final transcription
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.realtimeService.disconnect()
                        self.handleLiveRecordingComplete()
                    }
                }
            }
        } else {
            stopRecordingTimer()
            audioRecorder.stopRecording { [weak self] audioURL in
                guard let self = self else { return }
                self.realtimeService.disconnect()

                if let audioURL = audioURL {
                    self.setState(.transcribing)
                    self.processAudio(at: audioURL)
                } else {
                    self.showError("Erro ao gravar áudio")
                    self.setState(.idle)
                }
            }
        }
    }

    // MARK: - Live Recording Complete

    private func handleLiveRecordingComplete() {
        let liveText = liveTextInserter.allText

        if liveText.isEmpty {
            setState(.idle)
            return
        }

        lastTranscription = liveText

        if refinementLevel != .none {
            // Delete live text, refine, paste refined version
            setState(.refining)
            liveTextInserter.deleteAllInserted()

            Task {
                do {
                    let refined = try await refinementService.refine(text: liveText, level: refinementLevel)

                    await MainActor.run {
                        self.lastRefined = refined
                        self.showingResult = true
                        self.addToHistory(original: liveText, refined: refined)

                        if self.autoPaste {
                            self.pasteText(refined)
                        } else {
                            self.copyToClipboard(refined)
                        }

                        self.playSound(.complete)
                        self.setState(.idle)
                        self.livePartialText = ""

                        if self.showNotifications {
                            self.showNotification(text: refined)
                        }
                    }
                } catch {
                    await MainActor.run {
                        // Refinement failed - paste the live text as-is
                        self.lastRefined = liveText
                        self.showingResult = true
                        self.addToHistory(original: liveText, refined: liveText)

                        if self.autoPaste {
                            self.pasteText(liveText)
                        } else {
                            self.copyToClipboard(liveText)
                        }

                        self.showError("Refinamento falhou: \(error.localizedDescription)")
                        self.setState(.idle)
                        self.livePartialText = ""
                    }
                }
            }
        } else {
            // No refinement - paste final text
            lastRefined = liveText
            showingResult = true
            addToHistory(original: liveText, refined: liveText)

            if autoPaste {
                pasteText(liveText)
            } else {
                copyToClipboard(liveText)
            }

            playSound(.complete)
            setState(.idle)
            livePartialText = ""

            if showNotifications {
                showNotification(text: liveText)
            }
        }
    }

    // MARK: - Batch Processing

    private func processAudio(at url: URL) {
        Task {
            do {
                let transcription = try await whisperService.transcribe(audioURL: url)

                await MainActor.run {
                    self.lastTranscription = transcription
                }

                let finalText: String
                if refinementLevel != .none {
                    await MainActor.run { self.setState(.refining) }
                    finalText = try await refinementService.refine(text: transcription, level: refinementLevel)
                } else {
                    finalText = transcription
                }

                await MainActor.run {
                    self.lastRefined = finalText
                    self.showingResult = true
                    self.addToHistory(original: transcription, refined: finalText)

                    if self.autoPaste {
                        self.pasteText(finalText)
                    } else {
                        self.copyToClipboard(finalText)
                    }

                    self.playSound(.complete)
                    self.setState(.idle)

                    if self.showNotifications {
                        self.showNotification(text: finalText)
                    }
                }

                try? FileManager.default.removeItem(at: url)

            } catch {
                await MainActor.run {
                    self.showError("Erro: \(error.localizedDescription)")
                    self.setState(.idle)
                }
            }
        }
    }

    // MARK: - Output

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Recording Timer

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        audioLevel = 0
    }

    // MARK: - History

    private func addToHistory(original: String, refined: String) {
        let entry = DictationEntry(
            id: UUID(),
            date: Date(),
            original: original,
            refined: refined,
            refinementLevel: refinementLevel
        )
        history.insert(entry, at: 0)
        if history.count > 50 { history.removeLast() }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "dictation_history")
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "dictation_history"),
           let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) {
            history = entries
        }
    }

    // MARK: - State & UI

    private func setState(_ newState: DictationState) {
        state = newState
        onStateChange?(newState)
    }

    private func playSound(_ sound: DictationSound) {
        switch sound {
        case .start:
            NSSound(named: "Tink")?.play()
        case .complete:
            NSSound(named: "Glass")?.play()
        case .error:
            NSSound(named: "Basso")?.play()
        }
    }

    private func showError(_ message: String) {
        playSound(.error)
        showNotification(text: message)
    }

    private func showNotification(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Tachy"
        content.body = String(text.prefix(100))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func loadSettings() {
        if let level = settingsManager.refinementLevel {
            refinementLevel = level
        }
        autoPaste = settingsManager.autoPaste
        showNotifications = settingsManager.showNotifications
        useLiveTranscription = settingsManager.useLiveTranscription
    }

    func saveSettings() {
        settingsManager.refinementLevel = refinementLevel
        settingsManager.autoPaste = autoPaste
        settingsManager.showNotifications = showNotifications
        settingsManager.useLiveTranscription = useLiveTranscription
    }
}

// MARK: - RealtimeTranscriptionDelegate

extension DictationManager: RealtimeTranscriptionDelegate {
    func realtimeTranscription(didReceiveDelta text: String) {
        livePartialText += text
        liveTextInserter.appendDelta(text)
    }

    func realtimeTranscription(didCompleteTurn text: String) {
        liveTextInserter.commitTurn()
        // Keep livePartialText as-is — it shows ALL accumulated text in the panel.
        // Add a space separator so the next turn doesn't merge with the previous one.
        if !livePartialText.isEmpty && !livePartialText.hasSuffix(" ") {
            livePartialText += " "
        }
    }

    func realtimeTranscription(didEncounterError error: Error) {
        NSLog("[Tachy] Transcription error: \(error.localizedDescription)")
        // Show error to user if we're actively transcribing
        if state == .liveTranscribing || state == .paused {
            showError("Erro de transcrição: \(error.localizedDescription)")
        }

    }
}

// MARK: - Types

enum DictationSound {
    case start, complete, error
}

struct DictationEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let original: String
    let refined: String
    let refinementLevel: RefinementLevel
}
