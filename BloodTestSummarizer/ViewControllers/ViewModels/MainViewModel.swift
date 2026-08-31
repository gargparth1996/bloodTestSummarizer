//
//  MainViewModel.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 31/08/26.
//

import Foundation
import UIKit

protocol ActionableDelegate: AnyObject {
    func setLoading(_ isLoading: Bool)
    func update(phase: SummarizePhase, testsFound: Int)
    func complete(summary: BloodTestSummary)
    func presentError(_ error: Error)
}

class MainViewModel: NSObject, @unchecked Sendable {
    private let apiService: ClaudeAPIService
    private var summarizeTask: Task<Void, Never>?
    weak var delegate: ActionableDelegate?

    // We are using init here so as to make this class testable.
    init(apiService: ClaudeAPIService = ClaudeAPIService()) {
        self.apiService = apiService
    }

    func cancelLoading() {
        summarizeTask?.cancel()
        delegate?.setLoading(false)
    }
}

extension MainViewModel: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        summarizeTask = Task { [weak self] in
            await self?.processPDF(at: url)
        }
    }

    private func processPDF(at url: URL) async {
        delegate?.setLoading(true)

        // PDFs picked via UIDocumentPickerViewController may live outside
        // the app's sandbox, so we need security-scoped access to read them.
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let events = await apiService.summarize(pdfData: data)
            for try await event in events {
                switch event {
                case .progress(let phase, let testsFound):
                    delegate?.update(phase: phase, testsFound: testsFound)
                case .finished(let summary):
                    delegate?.complete(summary: summary)
                }
            }
        } catch {
            delegate?.setLoading(false)
            // The user tapped Cancel — no error to show.
            guard !Task.isCancelled else { return }
            delegate?.presentError(error)
        }
    }
}
