//
//  ClaudeAPIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewController: UIViewController {

    private let apiService = ClaudeAPIService()

    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "cross.case"))
        view.tintColor = .systemBlue
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let uploadButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Upload Blood Test PDF"
        config.image = UIImage(systemName: "doc.badge.plus")
        config.imagePadding = 8
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loadingView: LoadingIndicatorView = {
        let view = LoadingIndicatorView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var summarizeTask: Task<Void, Never>?

    private let disclaimerLabel: UILabel = {
        let label = UILabel()
        label.text = "This app gives a plain-language summary for reference only. It is not a diagnosis — always review results with a licensed physician."
        label.textColor = .tertiaryLabel
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Blood Test Summary"
        view.backgroundColor = .systemBackground
        setUpLayout()
        uploadButton.addTarget(self, action: #selector(didTapUpload), for: .touchUpInside)
        loadingView.onCancel = { [weak self] in self?.summarizeTask?.cancel() }
    }

    private func setUpLayout() {
        [iconView, uploadButton, loadingView, disclaimerLabel].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            iconView.bottomAnchor.constraint(equalTo: uploadButton.topAnchor, constant: -32),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            uploadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loadingView.topAnchor.constraint(equalTo: uploadButton.bottomAnchor, constant: 24),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            disclaimerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            disclaimerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            disclaimerLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    @objc private func didTapUpload() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func setLoading(_ loading: Bool) {
        uploadButton.isEnabled = !loading
        if loading {
            loadingView.start()
        } else {
            loadingView.stop()
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't summarize PDF",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension MainViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        summarizeTask = Task { await processPDF(at: url) }
    }

    private func processPDF(at url: URL) async {
        setLoading(true)

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
                    loadingView.update(phase: phase, testsFound: testsFound)
                case .finished(let summary):
                    loadingView.complete()
                    setLoading(false)
                    navigationController?.pushViewController(SummaryViewController(summary: summary), animated: true)
                }
            }
        } catch {
            setLoading(false)
            // The user tapped Cancel — no error to show.
            guard !Task.isCancelled else { return }
            presentError(error)
        }
    }
}
