
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation
import EvolutionMetadataModel

/* The swift-evolution-extraction tool can perform three tasks:
 1. Extract: Extraction of metadata to produce a json file
 2. Validate: Validation of proposals to ensure metadata can be extracted as expected (Not yet implemented)
 3. Snapshot: Capture a local snapshot of inputs and expected results that can be used for local testing
 
 An `ExtractionJob` captures all of the required inputs and potential output locations.
 */
public struct ExtractionJob: Sendable {
    public enum Source: Sendable {
        case network
        case snapshot(URL)
    }
    
    public enum Output: Sendable {
        case metadataJSON(URL)
        case snapshot(URL)
        case validationReport
        case none
    }
    
    let branchInfo: GitHubBranch?
    let proposalListing: [GitHubContentItem]? // Ad-hoc snapshots may not have these
    let proposalSpecs: [ProposalSpec]
    let previousResults: [Proposal]
    let expectedResults: [Proposal]?
    let forcedExtractionIDs: [String]
    let toolVersion: String
    let extractionDate: Date
    let output: Output
    let temporaryProposalsDirectory: URL?
    
    private init(output: Output, branchInfo: GitHubBranch? = nil, proposalListing: [GitHubContentItem]?, proposalSpecs: [ProposalSpec], previousResults: [Proposal], expectedResults: [Proposal]?, forcedExtractionIDs: [String], toolVersion: String, extractionDate: Date = Date()) {
        self.branchInfo = branchInfo
        self.proposalListing = proposalListing
        self.proposalSpecs = proposalSpecs
        self.previousResults = previousResults
        self.expectedResults = expectedResults
        self.forcedExtractionIDs = forcedExtractionIDs
        self.toolVersion = toolVersion
        self.extractionDate = extractionDate
        self.output = output
        self.temporaryProposalsDirectory = switch output {
            case .snapshot:
                FileManager.default.temporaryDirectory.appending(component: "proposals")
            default:
                nil
        }
    }
    
    public func run() async throws {
        // Extract Metadata
        let evolutionMetadata = try await EvolutionMetadataExtractor.extractEvolutionMetadata(for: self)
        
        // Compare results against expected results, if extraction job has them
        compareResultsToExpectedValuesIfPresent(evolutionMetadata)
        
        // Output Results
        try outputResults(evolutionMetadata)

    }
    
    public static func makeExtractionJob(from source: Source, output: Output, ignorePreviousResults: Bool = false, forcedExtractionIDs: [String] = [], toolVersion: String = "", extractionDate: Date = Date()) async throws -> ExtractionJob {
        switch source {
            case .network:
                try await networkExtractionJob(output: output, ignorePreviousResults: ignorePreviousResults, forcedExtractionIDs: forcedExtractionIDs, toolVersion: toolVersion, extractionDate: extractionDate)
            case .snapshot(let snapshotURL):
                try snapshotExtractionJob(from: snapshotURL, output: output, ignorePreviousResults: ignorePreviousResults, forcedExtractionIDs: forcedExtractionIDs, toolVersion: toolVersion, extractionDate: extractionDate)
        }
    }
        
    private static func snapshotExtractionJob(from snapshotURL: URL, output: Output, ignorePreviousResults: Bool, forcedExtractionIDs: [String], toolVersion: String, extractionDate: Date) throws -> ExtractionJob {
        
        // Argument validation should ensure correct values. Assert to catch problems in usage in tests.
        assert(snapshotURL.pathExtension == "evosnapshot", "Snapshot URL must be a directory with 'evosnapshot' extension.")
 
        verbosePrint("Using local snapshot\n'\(snapshotURL.relativePath)'")
        var proposalListingFound = false
        var previousResultsFound = false
                        
        let branchInfoURL = snapshotURL.appending(component: "source-info.json")
        let proposalListingURL = snapshotURL.appending(component: "proposal-listing.json")
        let previousResultsURL = snapshotURL.appending(component: "previous-results.json")
        let expectedResultsURL = snapshotURL.appending(component: "expected-results.json")
        let proposalDirectoryURL = snapshotURL.appending(component: "proposals")

        var proposalListing: [GitHubContentItem]? = nil
        var directoryContents: [ProposalSpec]
        var proposalSpecs: [ProposalSpec] = []
        var previousResults: [Proposal] = []
        
        let branchInfo = try FileUtilities.decode(GitHubBranch.self, from: branchInfoURL)
        
        directoryContents = try FileManager.default.contentsOfDirectory(at: proposalDirectoryURL, includingPropertiesForKeys: nil)
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .filter { $0.pathExtension == "md"}
            .map { ProposalSpec(url: $0, sha: "") } // try! SHA1.hexForData(Data(contentsOf: $0)))

        if let contentItems = try FileUtilities.decode([GitHubContentItem].self, from: proposalListingURL) {
            proposalListing = contentItems
            proposalSpecs = contentItems.map { ProposalSpec(url: snapshotURL.appending(path: $0.path), sha: $0.sha) }
            proposalListingFound = true
            if directoryContents.count != proposalSpecs.count {
                print("WARNING: Number of proposals in proposals directory does not match number of proposals in 'proposal-listing.json")
            }
        } else {
            proposalSpecs = directoryContents
        }
        
        if !ignorePreviousResults {
            if let previous = try FileUtilities.decode([Proposal].self, from: previousResultsURL) {
                previousResults = previous
                previousResultsFound = true
            }
        }
        
        let expectedResults = try FileUtilities.decode([Proposal].self, from: expectedResultsURL)
                    
        print(  """
                    proposal-listing.json found? \(proposalListingFound)
                    \(proposalListingFound ? "Will" : "Will not") use listing for proposal list and SHAs
                    
                    previous-results.json found? \(previousResultsFound)
                    \(previousResultsFound ? "Will use previous results unless --force-extract option is used" :
                       "Will extract values from all proposals")
                    
                    Proposal count: \(proposalSpecs.count)
                    """)
        
        // Expected test file directory structure:
        //
        // proposals/XXXX-proposal-files.md : Directory of proposal markdown files
        // expected-results.json            : Expected results from the source data. If present, will compare at end of run.
        // previous-results.json            : Previous results. If present, will reuse found proposal entries.
        // proposal-listing.json            : Results of GitHub query of proposals directory. Contains proposal SHA values.
        
        return ExtractionJob(output: output, branchInfo: branchInfo, proposalListing: proposalListing, proposalSpecs: proposalSpecs, previousResults: previousResults, expectedResults: expectedResults, forcedExtractionIDs: forcedExtractionIDs, toolVersion: toolVersion, extractionDate: extractionDate)
    }
    
    private static func networkExtractionJob(output: Output, ignorePreviousResults: Bool, forcedExtractionIDs: [String] = [], toolVersion: String = "", extractionDate: Date = Date()) async throws -> ExtractionJob {
        async let previousResults = ignorePreviousResults ? [] : PreviousResultsFetcher.fetchPreviousResults()
        
        let mainBranchInfo = try await GitHubFetcher.fetchMainBranch()
        async let proposalContentItems = GitHubFetcher.fetchProposalContentItems(for: mainBranchInfo.commit.sha)
        
        let proposalSpecs = try await proposalContentItems.map { $0.proposalSpec }
        
        return await ExtractionJob(output: output, branchInfo: mainBranchInfo, proposalListing: try proposalContentItems, proposalSpecs: proposalSpecs, previousResults: try await previousResults, expectedResults: nil, forcedExtractionIDs: forcedExtractionIDs, toolVersion: toolVersion, extractionDate: extractionDate)
    }

    
    private func compareResultsToExpectedValuesIfPresent(_ results: EvolutionMetadata) {

        guard let expectedResults else {
            return
        }

        let expectedResultsById = expectedResults.reduce(into: [:]) { $0[$1.id] = $1 }
        var passingProposals = 0
        var failingProposals = 0

        for newProposal in results.proposals {
            let id = newProposal.id
            guard !id.isEmpty  else {
                continue
            }
            guard let expectedResult = expectedResultsById[id] else {
                print("Could not find id \(id)")
                continue
            }
                        
            if newProposal == expectedResult {
                passingProposals += 1
            } else {
                failingProposals += 1
            }
        }
        
        verbosePrint("Comparing to snapshot expected results", terminator: "\n")
        verbosePrint("Passing Proposals:", passingProposals, terminator: "\n")
        verbosePrint("Failing Proposals:", failingProposals)
    }
    
    private func outputResults(_ results: EvolutionMetadata) throws {
        switch output {
            case .metadataJSON(let outputURL):
                try ExtractionJob.writeEvolutionResultsAsJSON(results: results, outputURL: outputURL)
            case .snapshot(let outputURL):
                try writeSnapshot(results: results, outputURL: outputURL)
            case .validationReport, .none:
                return
        }
    }
    
    private static func writeEvolutionResultsAsJSON(results: EvolutionMetadata, outputURL: URL) throws {
        print("Writing file '\(outputURL.lastPathComponent)' to '\(outputURL.absoluteURL.path())'\n")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(results.proposals)
        let directoryURL = outputURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: outputURL)
        
        // Temporarily write proposed new evolution-metadata.json file alongside legacy format file
        let newFormatFileURL = outputURL.deletingLastPathComponent().appending(component: "evolution-metadata.json")
        print("Writing file '\(newFormatFileURL.lastPathComponent)' to '\(newFormatFileURL.absoluteURL.path())'\n")
        
        let newFormatData = try encoder.encode(results)
        try newFormatData.write(to: newFormatFileURL)
    }
    
    private func writeSnapshot(results: EvolutionMetadata, outputURL: URL) throws {

        guard let temporaryProposalsDirectory else {
            fatalError("When snapshot command is being run temporaryProposalsDirectory should never be nil")
        }
        
        print("Writing snapshot '\(outputURL.lastPathComponent)' to '\(outputURL.absoluteURL.path())'\n")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        
        let proposalsDirectory = outputURL.appending(component: "proposals")
        try FileManager.default.moveItem(at: temporaryProposalsDirectory, to: proposalsDirectory)
    
        if let branchInfo {
            let branchInfoData = try encoder.encode(branchInfo)
            let branchInfoURL = outputURL.appending(component: "source-info.json")
            try branchInfoData.write(to: branchInfoURL)
        }
        
        if !proposalSpecs.isEmpty {
            let proposalListingData = try encoder.encode(proposalListing)
            let proposalListingURL = outputURL.appending(component: "proposal-listing.json")
            try proposalListingData.write(to: proposalListingURL)
        }

        let extractionResultsData = try encoder.encode(results.proposals)
        let expectedResultsURL = outputURL.appending(component: "expected-results.json")
        try extractionResultsData.write(to: expectedResultsURL)

    }
}
