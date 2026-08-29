import Foundation

enum ClaudeAPIError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case fileTooLarge
    case invalidResponse
    case server(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key is configured. See README.md — for a shipping app, point this at your own backend instead."
        case .fileTooLarge:
            return "This PDF is over the 32MB request limit. Try a smaller file."
        case .invalidResponse:
            return "The server sent back something this app didn't expect."
        case .server(let message):
            return message
        case .decoding(let error):
            return "Couldn't parse the summary Claude returned: \(error.localizedDescription)"
        }
    }
}

/// Sends a blood test PDF to Claude and parses back a structured summary.
///
/// ⚠️ SECURITY: as written, this talks to `api.anthropic.com` directly and
/// needs an API key in `Info.plist` at build time. That's fine for running
/// on your own device during development. It is **not** fine to ship — the
/// key can be extracted from the compiled binary by anyone who downloads
/// your app. Before distributing this app, change `baseURL` below to your
/// own backend endpoint that holds the real key server-side and forwards
/// the request (a minimal example is in `backend-example/`), and drop the
/// `x-api-key` header entirely from this client.
actor ClaudeAPIService {

    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let maxRequestBytes = 32 * 1024 * 1024 // Anthropic's documented request-size limit

    init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKey: String? = APIConfiguration.apiKey,
        model: String = "claude-sonnet-5"
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    func summarize(pdfData: Data) async throws -> BloodTestSummary {
        guard pdfData.count <= maxRequestBytes else { throw ClaudeAPIError.fileTooLarge }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Only needed when calling api.anthropic.com directly. Remove this
        // once you're going through your own backend proxy (see README).
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else {
            throw ClaudeAPIError.missingAPIKey
        }

        let payload = MessagesRequest(
            model: model,
            maxTokens: 2048,
            system: Self.systemPrompt,
            messages: [
                APIMessage(role: "user", content: [
                    .document(mediaType: "application/pdf", base64Data: pdfData.base64EncodedString()),
                    .text("Summarize this blood test report.")
                ])
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw ClaudeAPIError.server(body.error.message)
            }
            throw ClaudeAPIError.server("Request failed with status \(httpResponse.statusCode).")
        }

        let messageResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = messageResponse.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeAPIError.invalidResponse
        }

        let jsonText = Self.stripCodeFences(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else { throw ClaudeAPIError.invalidResponse }

        do {
            return try JSONDecoder().decode(BloodTestSummary.self, from: jsonData)
        } catch {
            throw ClaudeAPIError.decoding(error)
        }
    }

    /// Instructs Claude to read the PDF and answer with *only* JSON matching
    /// `BloodTestSummary`. Models sometimes wrap JSON in markdown fences
    /// despite instructions, so we defensively strip those before decoding.
    private static let systemPrompt = """
        You are helping summarize a patient's blood test report in the style \
        of a general physician explaining results in plain language. Read the \
        attached PDF and respond with ONLY a JSON object — no markdown fences, \
        no commentary before or after — matching exactly this schema:

        {
          "overallImpression": "one short paragraph in plain language",
          "findings": [
            {
              "testName": "string",
              "value": "string",
              "unit": "string",
              "referenceRange": "string",
              "flag": "normal" | "low" | "high" | "critical"
            }
          ],
          "recommendations": ["short, general, non-prescriptive suggestions"],
          "disclaimer": "a short reminder that this is not a diagnosis and the \
        patient should review results with a licensed physician"
        }

        Include every test value present in the report. If a reference range \
        or unit isn't printed in the document, say so rather than inventing one. \
        Never suggest a specific diagnosis, medication, or dosage.
        """

    private static func stripCodeFences(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
