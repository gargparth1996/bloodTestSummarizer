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

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

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
    }

    private func setUpLayout() {
        [iconView, uploadButton, activityIndicator, statusLabel, disclaimerLabel].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            iconView.bottomAnchor.constraint(equalTo: uploadButton.topAnchor, constant: -32),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            uploadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            activityIndicator.topAnchor.constraint(equalTo: uploadButton.bottomAnchor, constant: 24),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

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

    private func setLoading(_ loading: Bool, message: String?) {
        uploadButton.isEnabled = !loading
        statusLabel.text = message
        if loading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
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
        Task { await processPDF(at: url) }
    }

    private func processPDF(at url: URL) async {
        setLoading(true, message: "Reading PDF…")

        // PDFs picked via UIDocumentPickerViewController may live outside
        // the app's sandbox, so we need security-scoped access to read them.
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            setLoading(true, message: "Analyzing with Claude…")
            let summary = try await apiService.summarize(pdfData: data)
            setLoading(false, message: nil)
            navigationController?.pushViewController(SummaryViewController(summary: summary), animated: true)
        } catch {
            setLoading(false, message: nil)
            presentError(error)
        }
    }
}
