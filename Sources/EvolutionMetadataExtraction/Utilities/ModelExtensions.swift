//
//  ModelExtensions.swift
//  swift-evolution-metadata-extractor
//
//  Created by James Dempsey on 11/12/25.
//

import Foundation
import EvolutionMetadataModel

extension EvolutionMetadata {
    var jsonRepresentation: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            let adjustedData = JSONRewriter.applyRewritersToJSONData(rewriters: [JSONRewriter.prettyPrintVersions], data: data)
            return adjustedData
        }
    }

    var validationReport: String? {
        get throws {
            let errorProposals = proposals.filter { $0.hasErrors }
            let report = errorProposals.reduce(into: "") { $0 += $1.validationReport + "\n\n" }
            return report
        }
    }
}

extension Proposal {
    var hasErrors: Bool {
        if let errors, !errors.isEmpty { true } else { false }
    }
    var hasWarnings: Bool {
        if let warnings, !warnings.isEmpty { true } else { false }
    }

    var validationReport: String {
        var report: String = ""
        if hasErrors || hasWarnings {
            let adjustedID = id.isEmpty ? "Missing ID" : id
            let adjustedTitle = title.isEmpty ? "Missing Title" : "'\(title)'"
            report += (id.isEmpty && title.isEmpty) ? "Missing ID & Title" : "\(adjustedID) \(adjustedTitle)\n"
            report += link

            if hasErrors, let errors {
                report += "\n\n" + issuesReport(heading: "ERRORS", issues: errors)
            }
            if hasWarnings, let warnings {
                report += "\n\n" + issuesReport(heading: "WARNINGS", issues: warnings)
            }
        }
        return report
    }

    private func issuesReport(heading: String, issues: [Proposal.Issue]) -> String {
        var report = "\t\(heading)\n"
        for issue in issues {
            report += "\t\(issue.message) (Code \(issue.code))\n"
        }
        return report
    }
}
