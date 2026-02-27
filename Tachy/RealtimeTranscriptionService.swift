import Foundation

protocol RealtimeTranscriptionDelegate: AnyObject {
    func realtimeTranscription(didReceiveDelta text: String)
    func realtimeTranscription(didCompleteTurn text: String)
    func realtimeTranscription(didEncounterError error: Error)
}

class RealtimeTranscriptionService: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: RealtimeTranscriptionDelegate?

    /// Called when the WebSocket connection is established and ready.
    var onConnected: (() -> Void)?

    /// Called when the WebSocket connection fails.
    var onConnectionFailed: ((Error) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private(set) var isConnected = false

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect() {
        let apiKey = SettingsManager.shared.openAIKey
        guard !apiKey.isEmpty else {
            let error = DictationError.missingAPIKey("OpenAI API key não configurada")
            delegate?.realtimeTranscription(didEncounterError: error)
            onConnectionFailed?(error)
            return
        }

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // Connection timeout: if not connected within 10s, fire failure
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !self.isConnected, self.webSocketTask != nil else { return }
            NSLog("[Tachy] WebSocket connection timeout")
            let error = DictationError.apiError("WebSocket connection timeout (10s)")
            self.onConnectionFailed?(error)
            self.disconnect()
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        onConnected = nil
        onConnectionFailed = nil
    }

    func sendAudio(pcmData: Data) {
        guard isConnected else { return }

        let base64Audio = pcmData.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                NSLog("[Tachy] WebSocket send error: \(error)")
                self?.isConnected = false
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        NSLog("[Tachy] WebSocket connected")
        isConnected = true
        configureSession()
        receiveMessages()
        DispatchQueue.main.async { [weak self] in
            self?.onConnected?()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        NSLog("[Tachy] WebSocket closed: \(closeCode.rawValue)")
        let wasConnected = isConnected
        isConnected = false
        if !wasConnected {
            let error = DictationError.apiError("WebSocket closed: \(closeCode.rawValue)")
            DispatchQueue.main.async { [weak self] in
                self?.onConnectionFailed?(error)
            }
        }
    }

    // Handle connection-level errors (TLS, DNS, auth, etc.)
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("[Tachy] WebSocket connection error: \(error)")
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                self?.onConnectionFailed?(error)
                self?.delegate?.realtimeTranscription(didEncounterError: error)
            }
        }
    }

    // MARK: - Internal

    private func configureSession() {
        let config: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-mini-transcribe",
                    "language": "pt"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ],
                "input_audio_noise_reduction": [
                    "type": "near_field"
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        NSLog("[Tachy] Sending session config: \(jsonString)")

        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                NSLog("[Tachy] WebSocket config send error: \(error)")
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessages()

            case .failure(let error):
                NSLog("[Tachy] WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self?.delegate?.realtimeTranscription(didEncounterError: error)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            NSLog("[Tachy] Failed to parse message: \(text.prefix(200))")
            return
        }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                NSLog("[Tachy] Delta: \(delta)")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.realtimeTranscription(didReceiveDelta: delta)
                }
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                NSLog("[Tachy] Turn completed: \(transcript)")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.realtimeTranscription(didCompleteTurn: transcript)
                }
            }

        case "conversation.item.input_audio_transcription.failed":
            NSLog("[Tachy] Transcription failed: \(text.prefix(500))")
            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.realtimeTranscription(didEncounterError: DictationError.apiError("Transcription failed: \(message)"))
                }
            }

        case "error":
            NSLog("[Tachy] API error: \(text.prefix(500))")
            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.realtimeTranscription(didEncounterError: DictationError.apiError("Realtime API: \(message)"))
                }
            }

        case "transcription_session.created", "transcription_session.updated":
            NSLog("[Tachy] Session event: \(type)")

        case "input_audio_buffer.speech_started":
            NSLog("[Tachy] Speech started")

        case "input_audio_buffer.speech_stopped":
            NSLog("[Tachy] Speech stopped")

        case "input_audio_buffer.committed":
            NSLog("[Tachy] Audio buffer committed")

        case "conversation.item.created":
            NSLog("[Tachy] Conversation item created")

        default:
            NSLog("[Tachy] Unknown event: \(type) — \(text.prefix(300))")
        }
    }
}
