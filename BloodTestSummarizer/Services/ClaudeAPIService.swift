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
        maxTokens: Int = 64000
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    /// Streams a summary from Claude, yielding `.progress` events as the
    /// response arrives and a single terminal `.finished` event once the
    /// full JSON has been received and decoded.
    ///
    /// Cancelling the `Task` that is iterating the returned stream aborts
    /// the underlying request via `onTermination`.
    func summarize(pdfData: Data) -> AsyncThrowingStream<SummarizeEvent, Error> {
        AsyncThrowingStream { continuation in
            let fetchTask = Task {
                do {
                    try await self.runSummarize(pdfData: pdfData, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in fetchTask.cancel() }
        }
    }

    private func runSummarize(
        pdfData: Data,
        continuation: AsyncThrowingStream<SummarizeEvent, Error>.Continuation
    ) async throws {
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
            ],
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(payload)

        continuation.yield(.progress(phase: .uploading, testsFound: 0))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = try await Self.collectBody(from: bytes)
            if let errorBody = try? JSONDecoder().decode(APIErrorBody.self, from: body) {
                throw APIError.server(errorBody.error.message)
            }
            throw APIError.server("Request failed with status \(httpResponse.statusCode).")
        }

        var textBuffer = ""
        var currentPhase: SummarizePhase = .analyzing
        var stopReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonText = line.dropFirst("data: ".count)
            guard let chunkData = jsonText.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: chunkData) else {
                continue
            }

            switch chunk.type {
            case "content_block_delta":
                guard let delta = chunk.delta?.text else { continue }
                textBuffer += delta

                let testsFound = textBuffer.components(separatedBy: "\"testName\"").count - 1
                currentPhase = Self.phase(for: textBuffer)
                continuation.yield(.progress(phase: currentPhase, testsFound: testsFound))

            case "message_delta":
                stopReason = chunk.delta?.stopReason ?? stopReason

            case "error":
                throw APIError.server(chunk.error?.message ?? "The server reported a streaming error.")

            default:
                break
            }
        }

        guard !textBuffer.isEmpty else {
            throw APIError.incompleteResponse(stopReason: stopReason)
        }

        continuation.yield(.progress(phase: .finalizing, testsFound: textBuffer.components(separatedBy: "\"testName\"").count - 1))

        let jsonText = Self.stripCodeFences(from: textBuffer)
        guard let jsonData = jsonText.data(using: .utf8) else { throw APIError.invalidResponse }

        do {
            let summary = try JSONDecoder().decode(BloodTestSummary.self, from: jsonData)
            continuation.yield(.finished(summary))
        } catch {
            throw APIError.decoding(error)
        }
    }

    private static func phase(for buffer: String) -> SummarizePhase {
        if buffer.contains("\"disclaimer\"") { return .finalizing }
        if buffer.contains("\"recommendations\"") { return .buildingRecommendations }
        if buffer.contains("\"findings\"") { return .extractingFindings }
        return .analyzing
    }

    private static func collectBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
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
