//
//  ClaudeAPIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation


/// Sends a blood test PDF to Claude and parses back a structured summary.
///
/// ⚠️ SECURITY: as written, this talks to `api.anthropic.com` directly and
/// needs an API key in `Info.plist` at build time. That's fine for running
/// on your own device during development. It is **not** fine to ship — the
/// key can be extracted from the compiled binary by anyone who downloads
/// your app. Before distributing this app, change `baseURL` below to your
/// own backend endpoint that holds the real key server-side and forwards
/// the request and drop the`x-api-key` header entirely from this client.
actor ClaudeAPIService {

    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let maxTokens: Int
    private let maxRequestBytes: Int = 32 * 1024 * 1024 // Anthropic's documented request-size limit

    // We are using init here so as to make this class testable.
    // Event though all these properties could be hardcoded, that would have resulted in this class being unmockable.
    init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKey: String? = APIConfiguration.apiKey,
        model: String = "claude-sonnet-5",
        maxTokens: Int = 2048
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    func summarize(pdfData: Data) async throws -> BloodTestSummary {
        guard pdfData.count <= maxRequestBytes else { throw APIError.fileTooLarge }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else {
            throw APIError.missingAPIKey
        }

        let payload = MessagesRequest(
            model: model,
            maxTokens: maxTokens,
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
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw APIError.server(body.error.message)
            }
            throw APIError.server("Request failed with status \(httpResponse.statusCode).")
        }

        let messageResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = messageResponse.content.first(where: { $0.type == "text" })?.text else {
            throw APIError.invalidResponse
        }

        let jsonText = Self.stripCodeFences(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else { throw APIError.invalidResponse }

        do {
            return try JSONDecoder().decode(BloodTestSummary.self, from: jsonData)
        } catch {
            throw APIError.decoding(error)
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
