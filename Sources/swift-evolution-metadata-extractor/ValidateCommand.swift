//
//  ValidateCommand.swift
//  swift-evolution-metadata-extractor
//
//  Created by James Dempsey on 11/11/25.
//

import Foundation
import ArgumentParser
import EvolutionMetadataExtraction

struct ValidateCommand: AsyncParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: Help.Validate.commandName,
        abstract: Help.Validate.abstract,
        discussion: Help.Validate.discussion
    )
    
    @Option(name: [.short, .customLong("output-path")], help: Help.Shared.Argument.outputPath, transform: ArgumentValidation.Validate.output)
    var output: ExtractionJob.Output = ArgumentValidation.Validate.defaultOutput
    
    @Flag(name: .shortAndLong, help: Help.Shared.Argument.verbose)
    var verbose: Bool = false
    
    @Option(help: Help.Extract.Argument.forceExtract)
    var forceExtract: [String] = []
    var forceAll = false
    var forcedExtractionIDs: [String] = []
    
    @Option(name: .customLong("snapshot-path"), help: Help.Shared.Argument.snapshotPath, transform: ArgumentValidation.extractionSource)
    var extractionSource: ExtractionJob.Source = .network
    
//    @Option var basePath: String?
    @Argument var filenames: [String] = []

    
    mutating func validate() throws {
        ArgumentValidation.validate(verbose: verbose)
        ArgumentValidation.validateHTTPProxies()
        (forceAll, forcedExtractionIDs) = try ArgumentValidation.Extract.validate(forceExtract: forceExtract)
    }

    
    func run() async throws {
//        let baseURL = URL(filePath: basePath)
        let fileURLs = filenames.map { URL(filePath: $0) }
        let source: ExtractionJob.Source = .proposalFiles(fileURLs)
//        let source = extractionSource
        let extractionJob = try await ExtractionJob.makeExtractionJob(from: source, output: output, ignorePreviousResults: forceAll, forcedExtractionIDs: forcedExtractionIDs)
        try await extractionJob.run()
    }
}
