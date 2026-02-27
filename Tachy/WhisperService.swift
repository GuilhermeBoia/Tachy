import Foundation

class WhisperService {
    private let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    func transcribe(audioURL: URL) async throws -> String {
        let apiKey = SettingsManager.shared.openAIKey
        guard !apiKey.isEmpty else {
            throw DictationError.missingAPIKey("OpenAI API key não configurada")
        }

        let audioData = try Data(contentsOf: audioURL)
        let boundary = UUID().uuidString

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // Audio file
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.m4a", mimeType: "audio/m4a", data: audioData)

        // Model
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")

        // Language: leave empty for auto-detection (handles multilingual)
        // If you want to hint, use: body.appendMultipart(boundary: boundary, name: "language", value: "pt")

        // Prompt to help with context and mixed languages
        body.appendMultipart(
            boundary: boundary,
            name: "prompt",
            value: "Transcrição multilíngue. O falante pode alternar entre português brasileiro e inglês. Preserve code terms, technical terms, and programming keywords in their original language. Evite marcas de fala e hesitações (ex.: hum, ahn, tipo, é...). Retorne texto limpo e natural."
        )

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.networkError("Resposta inválida do servidor")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DictationError.apiError("Whisper API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }
}

struct WhisperResponse: Codable {
    let text: String
}

// MARK: - Multipart helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
