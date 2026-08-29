//
//  ClaudeAPIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import UIKit

@MainActor
final class SummaryViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case impression, findings, recommendations, disclaimer
    }

    private let summary: BloodTestSummary

    init(summary: BloodTestSummary) {
        self.summary = summary
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Summary"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "textCell")
        tableView.register(FindingCell.self, forCellReuseIdentifier: FindingCell.reuseID)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .impression: return 1
        case .findings: return summary.findings.count
        case .recommendations: return max(summary.recommendations.count, 1)
        case .disclaimer: return 1
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .impression: return "Overall Impression"
        case .findings: return "Key Findings"
        case .recommendations: return "Suggestions"
        case .disclaimer: return nil
        case .none: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .impression:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textCell", for: indexPath)
            configureBodyLabel(cell, text: summary.overallImpression)
            return cell

        case .findings:
            let cell = tableView.dequeueReusableCell(withIdentifier: FindingCell.reuseID, for: indexPath) as! FindingCell
            cell.configure(with: summary.findings[indexPath.row])
            return cell

        case .recommendations:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textCell", for: indexPath)
            if summary.recommendations.isEmpty {
                configureBodyLabel(cell, text: "No specific suggestions were included.")
            } else {
                configureBodyLabel(cell, text: "•  \(summary.recommendations[indexPath.row])")
            }
            return cell

        case .disclaimer, .none:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textCell", for: indexPath)
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = .italicSystemFont(ofSize: 13)
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.text = summary.disclaimer
            return cell
        }
    }

    private func configureBodyLabel(_ cell: UITableViewCell, text: String) {
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.textColor = .label
        cell.textLabel?.text = text
    }
}
