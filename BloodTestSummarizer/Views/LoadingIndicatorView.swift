//
//  LoadingIndicatorView.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import UIKit

/// A ring progress indicator with a pulsing icon and phase copy, driven by
/// real `SummarizePhase`/testsFound signal from the streaming API — not a
/// timer. Replaces the plain `UIActivityIndicatorView`, which gave no
/// indication of progress during the long wait on Claude's response.
@MainActor
final class LoadingIndicatorView: UIView {

    var onCancel: (() -> Void)?

    private let ringDiameter: CGFloat = 72

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "cross.case"))
        view.tintColor = .systemBlue
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        return button
    }()

    private var progressAnimator: UIViewPropertyAnimator?
    private var displayedProgress: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayout()
        setUpRing()
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUpLayout() {
        let ringContainer = UIView()
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.addSubview(iconView)

        let stack = UIStackView(arrangedSubviews: [ringContainer, statusLabel, detailLabel, cancelButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            ringContainer.widthAnchor.constraint(equalToConstant: ringDiameter),
            ringContainer.heightAnchor.constraint(equalToConstant: ringDiameter),

            iconView.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.ringContainer = ringContainer
    }

    /// Kept so `layoutSubviews` can size the ring paths against the
    /// container's actual bounds once Auto Layout has run.
    private var ringContainer: UIView?

    private func setUpRing() {
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.systemGray5.cgColor
        trackLayer.lineWidth = 4
        trackLayer.lineCap = .round

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0

        ringContainer?.layer.addSublayer(trackLayer)
        ringContainer?.layer.addSublayer(progressLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let ringContainer, ringContainer.bounds.width > 0 else { return }

        let path = UIBezierPath(
            arcCenter: CGPoint(x: ringContainer.bounds.midX, y: ringContainer.bounds.midY),
            radius: ringContainer.bounds.width / 2 - trackLayer.lineWidth / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        trackLayer.frame = ringContainer.bounds
        progressLayer.frame = ringContainer.bounds
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    func start() {
        isHidden = false
        displayedProgress = 0
        progressLayer.strokeEnd = 0
        iconView.addSymbolEffect(.pulse, options: .repeating)
        update(phase: .uploading, testsFound: 0)
    }

    func stop() {
        progressAnimator?.stopAnimation(true)
        iconView.removeAllSymbolEffects()
        isHidden = true
    }

    func update(phase: SummarizePhase, testsFound: Int) {
        statusLabel.text = Self.statusText(for: phase)
        detailLabel.text = Self.detailText(for: phase, testsFound: testsFound)
        animateProgress(to: Self.targetProgress(for: phase, testsFound: testsFound))
    }

    /// Called on the terminal success event to fill the ring the rest of
    /// the way before the screen transitions away.
    func complete() {
        animateProgress(to: 1)
    }

    private func animateProgress(to target: CGFloat) {
        guard target > displayedProgress else { return }
        progressAnimator?.stopAnimation(true)

        let animator = UIViewPropertyAnimator(duration: 0.5, curve: .easeOut) { [progressLayer] in
            progressLayer.strokeEnd = target
        }
        progressLayer.strokeEnd = displayedProgress
        animator.startAnimation()
        displayedProgress = target
        progressAnimator = animator
    }

    @objc private func didTapCancel() {
        onCancel?()
    }

    private static func statusText(for phase: SummarizePhase) -> String {
        switch phase {
        case .uploading: return "Uploading to Claude…"
        case .analyzing: return "Analyzing your blood test…"
        case .extractingFindings: return "Extracting test results…"
        case .buildingRecommendations: return "Preparing recommendations…"
        case .finalizing: return "Finalizing summary…"
        }
    }

    private static func detailText(for phase: SummarizePhase, testsFound: Int) -> String? {
        guard phase == .extractingFindings || phase == .buildingRecommendations || phase == .finalizing,
              testsFound > 0 else { return nil }
        return "\(testsFound) result\(testsFound == 1 ? "" : "s") found so far"
    }

    private static func targetProgress(for phase: SummarizePhase, testsFound: Int) -> CGFloat {
        switch phase {
        case .uploading: return 0.15
        case .analyzing: return 0.25
        case .extractingFindings: return min(0.45 + CGFloat(testsFound) * 0.03, 0.75)
        case .buildingRecommendations: return 0.85
        case .finalizing: return 0.95
        }
    }
}
