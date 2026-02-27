import Foundation

class RefinementService {
    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o-mini"

    func refine(text: String, level: RefinementLevel) async throws -> String {
        let apiKey = SettingsManager.shared.openAIKey
        guard !apiKey.isEmpty else {
            throw DictationError.missingAPIKey("OpenAI API key não configurada")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_completion_tokens": 700,
            "messages": [
                ["role": "system", "content": buildSystemPrompt(for: level)],
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
            throw DictationError.apiError("OpenAI refinement error (\(httpResponse.statusCode)): \(errorBody)")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let content = result.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        return content?.isEmpty == false ? content! : text
    }

    private func buildSystemPrompt(for level: RefinementLevel) -> String {
        let base = """
        Você é um assistente de refinamento de texto ditado por voz. O texto pode conter uma mistura de português brasileiro e inglês (especialmente termos técnicos de programação).

        REGRAS FUNDAMENTAIS:
        - NUNCA adicione conteúdo novo. Apenas refine o que foi ditado.
        - Preserve EXATAMENTE o idioma usado em cada trecho. Se o usuário falou em inglês, mantenha em inglês. Se falou em português, mantenha em português.
        - Preserve termos técnicos exatamente como falados (API, endpoint, React, useState, etc.)
        - Remova marcas de fala e hesitações sem mudar significado (ex.: "é...", "tipo", "hum", "ahn", "vamos lá", "certo?").
        - Retorne APENAS o texto refinado, sem explicações, comentários ou markdown.
        """

        switch level {
        case .none:
            return ""

        case .refine:
            return base + """

            NÍVEL: Refinamento
            - Foque em fluidez e limpeza de fala natural.
            - Remova repetições, cacoetes e conectores desnecessários.
            - Reestruture frases confusas para leitura clara, mantendo o significado original.
            - Se houver enumeração verbal ("ponto um", "primeiro", "segundo", etc.), converta para lista numerada (1., 2., 3.).
            - Preserve intenção, fatos e requisitos técnicos.
            """

        case .prompt:
            return base + """

            NÍVEL: Formatação como prompt técnico
            - Estruture o texto final como um prompt claro para IA.
            - Organize em blocos curtos: Contexto, Objetivo, Requisitos, Restrições, Saída esperada.
            - Use listas numeradas quando houver múltiplos itens.
            - Preserve todos os requisitos técnicos mencionados
            - Torne as instruções precisas e acionáveis
            - Mantenha os idiomas originais usados
            """
        }
    }
}

private struct OpenAIChatResponse: Codable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

private struct OpenAIMessage: Codable {
    let content: String?
}
