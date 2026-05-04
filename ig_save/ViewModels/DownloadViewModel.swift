//
//  DownloadViewModel.swift
//  ig_save
//

import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var jobs: [SaveJob] = []
    @Published private(set) var isWorking = false

    private let resolver = InstagramMediaResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()

    var canStart: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string {
            inputText = text
        }
        #endif
    }

    func start() {
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !input.isEmpty, !isWorking else {
            return
        }

        isWorking = true
        inputText = ""

        Task {
            await run(input: input)
        }
    }

    private func run(input: String) async {
        var job = SaveJob(input: input, status: .resolving)
        jobs.insert(job, at: 0)

        do {
            let assets = try await resolver.resolve(input)
            var savedCount = 0

            for (offset, asset) in assets.enumerated() {
                let current = offset + 1
                update(job.id, status: .downloading(current: current, total: assets.count))

                let fileURL = try await downloader.download(asset)

                update(job.id, status: .saving(current: current, total: assets.count))
                try await saver.save(fileURL: fileURL, kind: asset.kind)

                savedCount += 1
            }

            update(job.id, status: .saved(count: savedCount))
        } catch {
            update(job.id, status: .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }

        isWorking = false
        job.status = jobs.first(where: { $0.id == job.id })?.status ?? job.status
    }

    private func update(_ id: UUID, status: SaveStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        jobs[index].status = status
    }
}
