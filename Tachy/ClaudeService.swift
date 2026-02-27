import Foundation

class ClaudeService {
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    func refine(text: String, level: RefinementLevel) async throws -> String {
        let apiKey = SettingsManager.shared.anthropicKey
        guard !apiKey.isEmpty else {
            throw DictationError.missingAPIKey("Anthropic API key não configurada")
        }

        let systemPrompt = buildSystemPrompt(for: level)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.networkError("Resposta inválida do servidor")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DictationError.apiError("Claude API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return result.content.first?.text ?? text
    }

    private func buildSystemPrompt(for level: RefinementLevel) -> String {
        let base = """
        Você é um assistente de refinamento de texto ditado por voz. O texto pode conter uma mistura de português brasileiro e inglês (especialmente termos técnicos de programação).

        REGRAS FUNDAMENTAIS:
        - NUNCA adicione conteúdo novo. Apenas refine o que foi ditado.
        - Preserve EXATAMENTE o idioma usado em cada trecho. Se o usuário falou em inglês, mantenha em inglês. Se falou em português, mantenha em português.
        - Preserve termos técnicos exatamente como falados (API, endpoint, React, useState, etc.)
        - Retorne APENAS o texto refinado, sem explicações, comentários ou markdown.
        """

        switch level {
        case .none:
            return "" // Won't be called

        case .light:
            return base + """

            NÍVEL: Refinamento leve
            - Adicione pontuação correta (vírgulas, pontos, interrogações, etc.)
            - Corrija erros claros de transcrição
            - Mantenha o estilo e vocabulário original do falante
            - Não reescreva frases, apenas corrija pontuação e erros óbvios
            """

        case .moderate:
            return base + """

            NÍVEL: Refinamento moderado
            - Adicione pontuação correta
            - Corrija erros de transcrição
            - Melhore levemente a clareza e fluidez do texto
            - Reorganize frases confusas mantendo o significado original
            - Remova repetições e hesitações ("é... tipo... então...")
            - Mantenha o tom e estilo do falante
            """

        case .prompt:
            return base + """

            NÍVEL: Formatação como prompt técnico
            - Adicione pontuação e corrija erros
            - Estruture o texto como um prompt claro e eficaz
            - Use formatação adequada (listas se necessário)
            - Preserve todos os requisitos técnicos mencionados
            - Torne as instruções mais precisas e acionáveis
            - Mantenha os idiomas originais usados
            """
        }
    }
}

// MARK: - Response types

struct ClaudeResponse: Codable {
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let type: String
    let text: String
}
