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
    @Published private(set) var jobs: [SaveJob] = SaveJobStore.load()
    @Published private(set) var isWorking = false
    @Published private(set) var recentSaves: [RecentSave] = RecentSaveStore.load()
    @Published private(set) var hasInstagramSession = false
    @Published var isShowingInstagramLogin = false
    @Published var profileUsername = ""
    @Published private(set) var profilePosts: [InstagramProfilePost] = []
    @Published var selectedProfilePostIDs: Set<String> = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileError: String?

    private let resolver = InstagramMediaResolver()
    private let webStoryResolver = InstagramWebStoryResolver()
    private let profileFeedResolver = InstagramProfileFeedResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()
    private let thumbnailGenerator = ThumbnailGenerator()
    private var queueWorker: Task<Void, Never>?

    var canStart: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFetchProfile: Bool {
        !profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoadingProfile
    }

    var canSaveSelectedProfilePosts: Bool {
        !selectedProfilePostIDs.isEmpty && !isLoadingProfile
    }

    var profileRegularPosts: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .post }
    }

    var profileReels: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .reel }
    }

    var profileStories: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .story }
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

        guard !input.isEmpty else {
            return
        }

        inputText = ""
        enqueue(input: input)
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "igsave",
            url.host(percentEncoded: false)?.lowercased() == "import",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let importedURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
            !importedURL.isEmpty
        else {
            return false
        }

        enqueue(input: importedURL)
        return true
    }

    func fetchLatestProfilePosts() {
        let username = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !isLoadingProfile else {
            return
        }

        isLoadingProfile = true
        profileError = nil
        profilePosts = []
        selectedProfilePostIDs = []

        Task {
            do {
                profilePosts = try await profileFeedResolver.latestPosts(for: username, limitPerKind: 5)
            } catch {
                profileError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isLoadingProfile = false
        }
    }

    func toggleProfilePost(_ post: InstagramProfilePost) {
        if selectedProfilePostIDs.contains(post.id) {
            selectedProfilePostIDs.remove(post.id)
        } else {
            selectedProfilePostIDs.insert(post.id)
        }
    }

    func toggleAllProfilePosts(in posts: [InstagramProfilePost]) {
        let postIDs = Set(posts.map(\.id))

        guard !postIDs.isEmpty else {
            return
        }

        if postIDs.isSubset(of: selectedProfilePostIDs) {
            selectedProfilePostIDs.subtract(postIDs)
        } else {
            selectedProfilePostIDs.formUnion(postIDs)
        }
    }

    func saveSelectedProfilePosts() {
        let selectedPosts = profilePosts
            .filter { selectedProfilePostIDs.contains($0.id) }

        guard !selectedPosts.isEmpty else {
            return
        }

        for post in selectedPosts {
            enqueue(input: post.url.absoluteString)
        }

        selectedProfilePostIDs = []
    }

    func showInstagramLogin() {
        isShowingInstagramLogin = true
    }

    func finishInstagramLogin() {
        isShowingInstagramLogin = false

        Task {
            await refreshInstagramSessionStatus()
        }
    }

    func refreshInstagramSessionStatus() async {
        hasInstagramSession = await InstagramSessionStore.hasActiveSession()
    }

    func resumePendingJobs() {
        MediaDownloader.cleanCache()
        ensureQueueProcessing()
    }

    func retry(_ job: SaveJob, allowDuplicate: Bool = false) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        jobs[index].status = .queued
        jobs[index].allowsDuplicate = allowDuplicate || jobs[index].allowsDuplicate
        persistJobs()
        ensureQueueProcessing()
    }

    func cancel(_ job: SaveJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        if jobs[index].status.isRunning {
            queueWorker?.cancel()
            queueWorker = nil
        }

        jobs[index].status = .cancelled
        persistJobs()
        isWorking = jobs.contains { $0.status.isRunning }

        Task {
            await Task.yield()
            ensureQueueProcessing()
        }
    }

    func remove(_ job: SaveJob) {
        guard !job.status.isRunning else {
            return
        }

        jobs.removeAll { $0.id == job.id }
        persistJobs()
    }

    func clearFinishedJobs() {
        jobs.removeAll { $0.status.isTerminal }
        persistJobs()
    }

    private func enqueue(input: String, allowsDuplicate: Bool = false) {
        jobs.insert(SaveJob(input: input, allowsDuplicate: allowsDuplicate), at: 0)
        persistJobs()
        ensureQueueProcessing()
    }

    private func ensureQueueProcessing() {
        guard queueWorker == nil, jobs.contains(where: { $0.status == .queued }) else {
            return
        }

        queueWorker = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        isWorking = true

        while !Task.isCancelled,
              let job = jobs
                .filter({ $0.status == .queued })
                .min(by: { $0.createdAt < $1.createdAt }) {
            await run(jobID: job.id)
        }

        queueWorker = nil
        isWorking = jobs.contains { $0.status.isRunning }

        if jobs.contains(where: { $0.status == .queued }) {
            ensureQueueProcessing()
        }
    }

    private func run(jobID: UUID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            return
        }

        let input = job.input
        update(jobID, status: .resolving)

        do {
            try Task.checkCancellation()
            let resolution = try await resolveMedia(input)

            if !job.allowsDuplicate,
               let previousSave = RecentSaveStore.previousSave(for: resolution.sourceURL.absoluteString) {
                update(jobID, status: .duplicate(previousSavedAt: previousSave.savedAt))
                return
            }

            let assets = resolution.assets
            var savedCount = 0
            var downloadedMedia: [DownloadedMedia] = []

            for (offset, asset) in assets.enumerated() {
                try Task.checkCancellation()
                let current = offset + 1
                update(jobID, status: .downloading(current: current, total: assets.count))

                let fileURL = try await downloader.download(asset)
                downloadedMedia.append(DownloadedMedia(fileURL: fileURL, kind: asset.kind))

                update(jobID, status: .saving(current: current, total: assets.count))
                try await saver.save(fileURL: fileURL, kind: asset.kind)

                savedCount += 1
            }

            addRecentSave(input: input, resolution: resolution, downloadedMedia: downloadedMedia, savedCount: savedCount)
            update(jobID, status: .saved(count: savedCount))
            MediaDownloader.cleanCache()
        } catch is CancellationError {
            update(jobID, status: .cancelled)
        } catch {
            update(jobID, status: .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }
    }

    private func resolveMedia(_ input: String) async throws -> MediaResolution {
        guard isStoryInput(input) else {
            return try await resolver.resolve(input)
        }

        await refreshInstagramSessionStatus()

        guard hasInstagramSession else {
            throw MediaResolverError.storyLoginRequired
        }

        return try await webStoryResolver.resolve(input)
    }

    private func update(_ id: UUID, status: SaveStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        jobs[index].status = status
        persistJobs()
    }

    private func persistJobs() {
        SaveJobStore.persist(jobs)
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

    private func isStoryInput(_ input: String) -> Bool {
        guard let url = URL(string: input) else {
            return input.contains("/stories/")
        }

        return url.pathComponents.contains("stories")
    }
}

private struct DownloadedMedia {
    let fileURL: URL
    let kind: MediaKind
}
