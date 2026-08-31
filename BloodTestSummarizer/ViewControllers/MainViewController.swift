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
    private let viewModel: MainViewModel

    // We are using init here so as to make this class testable.
    init(viewModel: MainViewModel = MainViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        viewModel.delegate = self
        uploadButton.addTarget(self, action: #selector(didTapUpload), for: .touchUpInside)
        loadingView.onCancel = { [weak self] in self?.viewModel.cancelLoading() }
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
        picker.delegate = self.viewModel
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
}

extension MainViewController: @MainActor ActionableDelegate {
    func setLoading(_ loading: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            uploadButton.isEnabled = !loading
            if loading {
                loadingView.start()
            } else {
                loadingView.stop()
            }
        }
    }
    
    func update(phase: SummarizePhase, testsFound: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            loadingView.update(phase: phase, testsFound: testsFound)
        }
    }
    
    func complete(summary: BloodTestSummary) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            setLoading(false)
            navigationController?.pushViewController(SummaryViewController(summary: summary), animated: true)
        }
    }
    
    func presentError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: "Couldn't summarize PDF",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
