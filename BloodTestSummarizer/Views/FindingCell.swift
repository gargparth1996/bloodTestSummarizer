//
//  ClaudeAPIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import UIKit

final class FindingCell: UITableViewCell {

    static let reuseID = "FindingCell"

    private let nameLabel = UILabel()
    private let valueLabel = UILabel()
    private let rangeLabel = UILabel()
    private let flagBadge = PaddedLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpLayout() {
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        rangeLabel.font = .preferredFont(forTextStyle: .caption1)
        rangeLabel.textColor = .tertiaryLabel

        flagBadge.font = .boldSystemFont(ofSize: 11)
        flagBadge.textAlignment = .center
        flagBadge.layer.cornerRadius = 8
        flagBadge.layer.masksToBounds = true
        flagBadge.setContentHuggingPriority(.required, for: .horizontal)
        flagBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, valueLabel, rangeLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let rowStack = UIStackView(arrangedSubviews: [textStack, flagBadge])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            flagBadge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func configure(with finding: BloodTestSummary.Finding) {
        nameLabel.text = finding.testName
        valueLabel.text = finding.unit.isEmpty ? finding.value : "\(finding.value) \(finding.unit)"
        rangeLabel.text = finding.referenceRange.isEmpty ? nil : "Reference: \(finding.referenceRange)"
        flagBadge.text = finding.flag.rawValue.uppercased()

        let (background, tint): (UIColor, UIColor)
        switch finding.flag {
        case .normal: (background, tint) = (.systemGreen, .systemGreen)
        case .low: (background, tint) = (.systemBlue, .systemBlue)
        case .high: (background, tint) = (.systemOrange, .systemOrange)
        case .critical: (background, tint) = (.systemRed, .systemRed)
        }
        flagBadge.backgroundColor = background.withAlphaComponent(0.15)
        flagBadge.textColor = tint
    }
}

/// A UILabel with a bit of horizontal breathing room, used for the flag badge.
private final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + inset.left + inset.right, height: size.height + inset.top + inset.bottom)
    }
}
