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
    @Published private(set) var instagramSessionState: InstagramSessionState = .disconnected
    @Published var isShowingInstagramLogin = false
    @Published private(set) var previewResolution: MediaResolution?
    @Published var selectedPreviewAssetIDs: Set<UUID> = []
    @Published var isShowingPreview = false
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var previewError: String?
    @Published var profileUsername = ""
    @Published private(set) var profilePosts: [InstagramProfilePost] = []
    @Published var selectedProfilePostIDs: Set<String> = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileError: String?
    @Published private(set) var favoriteProfiles: [FavoriteProfile] = FavoriteProfileStore.load()
    @Published private(set) var lastProfileNewContentCount = 0

    private let resolver = InstagramMediaResolver()
    private let webStoryResolver = InstagramWebStoryResolver()
    private let profileFeedResolver = InstagramProfileFeedResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()
    private let thumbnailGenerator = ThumbnailGenerator()
    private var queueWorker: Task<Void, Never>?
    private var preparedResolutions: [UUID: MediaResolution] = [:]

    init() {
        AppPreferences.registerDefaults()
    }

    var canStart: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPreparingPreview
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

    var isCurrentProfileFavorite: Bool {
        guard let username = normalizedProfileUsername(profileUsername) else { return false }
        return favoriteProfiles.contains { $0.username.caseInsensitiveCompare(username) == .orderedSame }
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

        if !AppPreferences.previewsBeforeSaving {
            inputText = ""
            enqueue(input: input)
            return
        }

        isPreparingPreview = true
        previewError = nil

        Task {
            do {
                let resolution = try await resolveMedia(input)
                previewResolution = resolution
                selectedPreviewAssetIDs = Set(resolution.assets.map(\.id))
                isShowingPreview = true
                inputText = ""
            } catch {
                previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isPreparingPreview = false
        }
    }

    func togglePreviewAsset(_ asset: MediaAsset) {
        if selectedPreviewAssetIDs.contains(asset.id) {
            selectedPreviewAssetIDs.remove(asset.id)
        } else {
            selectedPreviewAssetIDs.insert(asset.id)
        }
    }

    func confirmPreviewSave() {
        guard let resolution = previewResolution else {
            return
        }

        let assets = resolution.assets.filter { selectedPreviewAssetIDs.contains($0.id) }
        guard !assets.isEmpty else {
            return
        }

        let selectedResolution = MediaResolution(
            assets: assets,
            username: resolution.username,
            contentKind: resolution.contentKind,
            sourceURL: resolution.sourceURL
        )
        enqueue(input: resolution.sourceURL.absoluteString, preparedResolution: selectedResolution)
        dismissPreview()
    }

    func dismissPreview() {
        isShowingPreview = false
        previewResolution = nil
        selectedPreviewAssetIDs = []
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
                let posts = try await profileFeedResolver.latestPosts(for: username, limitPerKind: 5)
                profilePosts = posts
                updateFavoriteSnapshot(for: username, posts: posts)
            } catch {
                profileError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isLoadingProfile = false
        }
    }

    func toggleCurrentProfileFavorite() {
        guard let username = normalizedProfileUsername(profileUsername) else {
            return
        }

        if let index = favoriteProfiles.firstIndex(where: {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        }) {
            favoriteProfiles.remove(at: index)
        } else {
            favoriteProfiles.append(FavoriteProfile(
                username: username,
                lastKnownPostIDs: Set(profilePosts.map(\.id))
            ))
        }
        FavoriteProfileStore.persist(favoriteProfiles)
    }

    func selectFavoriteProfile(_ favorite: FavoriteProfile) {
        profileUsername = favorite.username
        fetchLatestProfilePosts()
    }

    func removeFavoriteProfile(_ favorite: FavoriteProfile) {
        favoriteProfiles.removeAll { $0.id == favorite.id }
        FavoriteProfileStore.persist(favoriteProfiles)
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
        instagramSessionState = await InstagramSessionStore.validatedSessionState()
        hasInstagramSession = instagramSessionState.isConnected
    }

    func logoutInstagram() {
        Task {
            await InstagramSessionStore.clearInstagramSession()
            await refreshInstagramSessionStatus()
        }
    }

    func saveAgain(_ save: RecentSave) {
        enqueue(input: save.sourceURL, allowsDuplicate: true)
    }

    func deleteRecentSave(_ save: RecentSave) {
        recentSaves = RecentSaveStore.remove(save, from: recentSaves)
    }

    func clearRecentSaves() {
        recentSaves = RecentSaveStore.removeAll(from: recentSaves)
    }

    func copyRecentLink(_ save: RecentSave) {
        #if canImport(UIKit)
        UIPasteboard.general.string = save.sourceURL
        #endif
    }

    func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func resumePendingJobs() {
        MediaDownloader.cleanCache()
        consumePendingImports()
        ensureQueueProcessing()
    }

    func consumePendingImports() {
        for link in PendingImportStore.consumeAll() {
            enqueue(input: link)
        }
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

    private func enqueue(
        input: String,
        allowsDuplicate: Bool = false,
        preparedResolution: MediaResolution? = nil
    ) {
        let job = SaveJob(input: input, allowsDuplicate: allowsDuplicate)
        jobs.insert(job, at: 0)
        if let preparedResolution {
            preparedResolutions[job.id] = preparedResolution
        }
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
            let resolution: MediaResolution
            if let preparedResolution = preparedResolutions.removeValue(forKey: jobID) {
                resolution = preparedResolution
            } else {
                resolution = try await resolveMedia(input)
            }

            if AppPreferences.protectsAgainstDuplicates,
               !job.allowsDuplicate,
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

                let fileURL = try await downloader.download(
                    asset,
                    allowsCellularAccess: AppPreferences.allowsCellularDownloads
                )
                downloadedMedia.append(DownloadedMedia(fileURL: fileURL, kind: asset.kind))

                update(jobID, status: .saving(current: current, total: assets.count))
                try await saver.save(
                    fileURL: fileURL,
                    kind: asset.kind,
                    albumName: AppPreferences.usesDedicatedAlbum ? AppPreferences.dedicatedAlbumName : nil
                )

                savedCount += 1
            }

            await addRecentSave(input: input, resolution: resolution, downloadedMedia: downloadedMedia, savedCount: savedCount)
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
    ) async {
        guard savedCount > 0 else {
            return
        }

        let previewSource = downloadedMedia.first(where: { $0.kind == .image }) ?? downloadedMedia.first
        let previewFilename: String?
        if let previewSource {
            previewFilename = await thumbnailGenerator.makeThumbnail(for: previewSource.fileURL, kind: previewSource.kind)
        } else {
            previewFilename = nil
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

    private func normalizedProfileUsername(_ rawValue: String) -> String? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !value.isEmpty else { return nil }
        return value.lowercased()
    }

    private func updateFavoriteSnapshot(for rawUsername: String, posts: [InstagramProfilePost]) {
        guard
            let username = normalizedProfileUsername(rawUsername),
            let index = favoriteProfiles.firstIndex(where: {
                $0.username.caseInsensitiveCompare(username) == .orderedSame
            })
        else {
            lastProfileNewContentCount = 0
            return
        }

        let currentIDs = Set(posts.filter { $0.contentKind != .story }.map(\.id))
        let previousIDs = favoriteProfiles[index].lastKnownPostIDs
        lastProfileNewContentCount = previousIDs.isEmpty ? 0 : currentIDs.subtracting(previousIDs).count
        favoriteProfiles[index].lastKnownPostIDs = currentIDs
        FavoriteProfileStore.persist(favoriteProfiles)
    }
}

private struct DownloadedMedia {
    let fileURL: URL
    let kind: MediaKind
}
