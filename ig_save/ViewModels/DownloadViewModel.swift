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
    @Published private(set) var recentSaves: [RecentSave] = RecentSaveStore.load()

    private let resolver = InstagramMediaResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()
    private let thumbnailGenerator = ThumbnailGenerator()

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
            let resolution = try await resolver.resolve(input)
            let assets = resolution.assets
            var savedCount = 0
            var downloadedMedia: [DownloadedMedia] = []

            for (offset, asset) in assets.enumerated() {
                let current = offset + 1
                update(job.id, status: .downloading(current: current, total: assets.count))

                let fileURL = try await downloader.download(asset)
                downloadedMedia.append(DownloadedMedia(fileURL: fileURL, kind: asset.kind))

                update(job.id, status: .saving(current: current, total: assets.count))
                try await saver.save(fileURL: fileURL, kind: asset.kind)

                savedCount += 1
            }

            addRecentSave(input: input, resolution: resolution, downloadedMedia: downloadedMedia, savedCount: savedCount)
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

    private func addRecentSave(
        input: String,
        resolution: MediaResolution,
        downloadedMedia: [DownloadedMedia],
        savedCount: Int
    ) {
        guard savedCount > 0 else {
            return
        }

        let previewSource = downloadedMedia.first(where: { $0.kind == .image }) ?? downloadedMedia.first
        let previewFilename = previewSource.flatMap {
            thumbnailGenerator.makeThumbnail(for: $0.fileURL, kind: $0.kind)
        }
        let save = RecentSave(
            username: displayUsername(from: resolution, input: input),
            itemCount: savedCount,
            contentKind: resolution.contentKind,
            sourceURL: resolution.sourceURL.absoluteString,
            previewFilename: previewFilename
        )

        recentSaves = RecentSaveStore.add(save, to: recentSaves)
    }

    private func displayUsername(from resolution: MediaResolution, input: String) -> String {
        if let username = resolution.username, !username.isEmpty {
            return "@\(username)"
        }

        guard
            let url = URL(string: input),
            let host = url.host(percentEncoded: false)
        else {
            return "Instagram"
        }

        if host.contains("instagram.com") {
            return "Instagram"
        }

        return host
    }
}

private struct DownloadedMedia {
    let fileURL: URL
    let kind: MediaKind
}
