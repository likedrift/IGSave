//
//  ContentView.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()
    @State private var selectedTab: AppTab = .save
    @State private var inputMode: SaveInputMode = .link
    @State private var profileContentFilter: ProfileContentFilter = .post
    @State private var recentContentFilter: RecentContentFilter = .all
    @State private var mediaLibraryScope: MediaLibraryScope = .all
    @State private var recentSearchText = ""
    @State private var isShowingSettings = false
    @State private var isShowingCollectionManager = false
    @State private var isShowingClearLibraryConfirmation = false
    @State private var selectedRecentSave: RecentSave?
    @FocusState private var isInputFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("保存", systemImage: "square.and.arrow.down", value: AppTab.save) {
                saveNavigation
            }

            Tab("媒体库", systemImage: "square.stack.3d.up", value: AppTab.recents) {
                recentsNavigation
            }
        }
        .tint(Brand.accent)
        .tabBarMinimizeBehavior(.never)
        .onOpenURL { url in
            if viewModel.handleIncomingURL(url) {
                selectedTab = .save
                inputMode = .link
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .igSavePendingImport)) { _ in
            viewModel.consumePendingImports()
            selectedTab = .save
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.consumePendingImports()
            }
        }
        .task {
            await viewModel.refreshInstagramSessionStatus()
            viewModel.resumePendingJobs()
        }
        .sheet(
            isPresented: $viewModel.isShowingInstagramLogin,
            onDismiss: {
                Task {
                    await viewModel.refreshInstagramSessionStatus()
                }
            }
        ) {
            InstagramLoginView {
                viewModel.finishInstagramLogin()
            }
        }
        .sheet(isPresented: $viewModel.isShowingPreview, onDismiss: viewModel.dismissPreview) {
            if let resolution = viewModel.previewResolution {
                MediaPreviewView(
                    resolution: resolution,
                    selectedAssetIDs: viewModel.selectedPreviewAssetIDs,
                    onToggle: viewModel.togglePreviewAsset,
                    onCancel: viewModel.dismissPreview,
                    onConfirm: viewModel.confirmPreviewSave
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                sessionState: viewModel.instagramSessionState,
                isWorking: viewModel.isWorking,
                onLogin: {
                    isShowingSettings = false
                    Task { @MainActor in
                        await Task.yield()
                        viewModel.showInstagramLogin()
                    }
                },
                onLogout: viewModel.logoutInstagram,
                onOpenSettings: viewModel.openAppSettings
            )
        }
        .sheet(isPresented: $isShowingCollectionManager) {
            CollectionManagerView(
                collections: viewModel.mediaCollections,
                itemCount: { collection in
                    viewModel.recentSaves.lazy.filter { $0.collectionIDs.contains(collection.id) }.count
                },
                onCreate: viewModel.createMediaCollection,
                onRename: viewModel.renameMediaCollection,
                onDelete: { collection in
                    let updatedCollections = viewModel.deleteMediaCollection(collection)
                    if mediaLibraryScope == .collection(collection.id) {
                        mediaLibraryScope = .all
                    }
                    return updatedCollections
                }
            )
        }
        .sheet(item: $selectedRecentSave) { save in
            RecentSaveDetailView(
                save: save,
                collections: viewModel.mediaCollections,
                onOpen: {
                    if let url = URL(string: save.sourceURL) { openURL(url) }
                },
                onCopy: { viewModel.copyRecentLink(save) },
                onUpdateMetadata: { isFavorite, collectionIDs, tags, note in
                    if let updated = viewModel.updateRecentSaveMetadata(
                        save,
                        isFavorite: isFavorite,
                        collectionIDs: collectionIDs,
                        tags: tags,
                        note: note
                    ) {
                        selectedRecentSave = updated
                    }
                },
                onSaveAgain: {
                    viewModel.saveAgain(save)
                    selectedRecentSave = nil
                },
                onDelete: {
                    viewModel.deleteRecentSave(save)
                    selectedRecentSave = nil
                }
            )
        }
    }

    private var saveNavigation: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 24) {
                        linkComposer
                        profilePostsSection
                        taskQueueSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("IGSave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")

                    Button {
                        viewModel.showInstagramLogin()
                    } label: {
                        Image(systemName: viewModel.hasInstagramSession ? "checkmark.circle.fill" : "person.crop.circle")
                    }
                    .accessibilityLabel(viewModel.hasInstagramSession ? "Instagram 已登录" : "登录 Instagram")
                }
            }
        }
    }

    private var recentsNavigation: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                if filteredRecentSaves.isEmpty,
                   recentSearchText.isEmpty,
                   recentContentFilter == .all,
                   mediaLibraryScope == .all {
                    ContentUnavailableView(
                        "媒体库还是空的",
                        systemImage: "photo.stack",
                        description: Text("保存成功的帖子、Reel 和快拍会自动加入这里。")
                    )
                } else {
                    VStack(spacing: 12) {
                        libraryScopeBar

                        Picker("内容类型", selection: $recentContentFilter) {
                            ForEach(RecentContentFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        if filteredRecentSaves.isEmpty {
                            ContentUnavailableView(
                                filteredLibraryEmptyState.title,
                                systemImage: filteredLibraryEmptyState.systemImage,
                                description: Text(filteredLibraryEmptyState.description)
                            )
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(groupedRecentSaves) { group in
                                        Section {
                                            ForEach(group.saves) { save in
                                                RecentSaveRow(
                                                    save: save,
                                                    collections: viewModel.mediaCollections,
                                                    onSelect: { selectedRecentSave = save },
                                                    onToggleFavorite: {
                                                        _ = viewModel.toggleFavorite(save)
                                                    },
                                                    onOpen: {
                                                        if let url = URL(string: save.sourceURL) { openURL(url) }
                                                    },
                                                    onCopy: { viewModel.copyRecentLink(save) },
                                                    onSaveAgain: { viewModel.saveAgain(save) },
                                                    onDelete: { viewModel.deleteRecentSave(save) }
                                                )
                                            }
                                        } header: {
                                            Text(group.title)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                                .textCase(.uppercase)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 6)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 36)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("媒体库")
            .navigationBarTitleDisplayMode(.large)
            .recentSearchable(
                enabled: !viewModel.recentSaves.isEmpty,
                text: $recentSearchText
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Label("\(viewModel.recentSaves.count) 条媒体记录", systemImage: "photo.stack")
                        Button("管理收藏夹", systemImage: "folder.badge.gearshape") {
                            isShowingCollectionManager = true
                        }
                        Divider()
                        Button("清空全部记录", role: .destructive) {
                            isShowingClearLibraryConfirmation = true
                        }
                        .disabled(viewModel.recentSaves.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("媒体库菜单")
                }
            }
            .confirmationDialog(
                "清空全部媒体库记录？",
                isPresented: $isShowingClearLibraryConfirmation
            ) {
                Button("清空记录", role: .destructive) {
                    viewModel.clearRecentSaves()
                    mediaLibraryScope = .all
                    recentSearchText = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("系统照片不会被删除，但标签、备注和收藏关系会随记录一同移除。")
            }
        }
    }

    private var filteredRecentSaves: [RecentSave] {
        let query = recentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.recentSaves.filter { save in
            let matchesKind = recentContentFilter.matches(save.contentKind)
            let matchesScope: Bool = switch mediaLibraryScope {
            case .all: true
            case .favorites: save.isFavorite
            case let .collection(id): save.collectionIDs.contains(id)
            }
            let collectionNames = viewModel.mediaCollections
                .filter { save.collectionIDs.contains($0.id) }
                .map(\.name)
            let matchesQuery = query.isEmpty ||
                save.username.lowercased().contains(query) ||
                save.tags.contains { $0.lowercased().contains(query) } ||
                (save.note?.lowercased().contains(query) ?? false) ||
                collectionNames.contains { $0.lowercased().contains(query) }
            return matchesKind && matchesScope && matchesQuery
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    private var groupedRecentSaves: [RecentSaveGroup] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        let currentMonth = calendar.dateInterval(of: .month, for: Date())
        var orderedTitles: [String] = []
        var grouped: [String: [RecentSave]] = [:]

        for save in filteredRecentSaves {
            let title: String
            if calendar.isDateInToday(save.savedAt) {
                title = "今天"
            } else if calendar.isDateInYesterday(save.savedAt) {
                title = "昨天"
            } else if let startOfWeek, save.savedAt >= startOfWeek {
                title = "本周"
            } else if currentMonth?.contains(save.savedAt) == true {
                title = "本月"
            } else {
                title = Self.libraryMonthFormatter.string(from: save.savedAt)
            }

            if grouped[title] == nil {
                orderedTitles.append(title)
            }
            grouped[title, default: []].append(save)
        }

        return orderedTitles.compactMap { title in
            guard let saves = grouped[title], !saves.isEmpty else { return nil }
            return RecentSaveGroup(title: title, saves: saves)
        }
    }

    private static let libraryMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private var filteredLibraryEmptyState: (title: String, systemImage: String, description: String) {
        if !recentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (
                "没有匹配的记录",
                "magnifyingglass",
                "试试缩短关键词，或调整收藏夹和内容类型。"
            )
        }

        switch mediaLibraryScope {
        case .favorites:
            return (
                "还没有收藏内容",
                "star",
                "轻点媒体卡片上的星标，常用内容会集中显示在这里。"
            )
        case .collection:
            return (
                "这个收藏夹还是空的",
                "folder",
                "打开媒体详情，在“整理信息”中把内容加入收藏夹。"
            )
        case .all:
            break
        }

        if recentContentFilter != .all {
            return (
                "还没有(recentContentFilter.title)内容",
                "line.3.horizontal.decrease.circle",
                "选择其他内容类型，或继续保存新的 Instagram 内容。"
            )
        }

        return (
            "没有匹配的记录",
            "line.3.horizontal.decrease.circle",
            "试试调整收藏夹、内容类型或搜索关键词。"
        )
    }

    private var libraryScopeBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                libraryScopeButton(title: "全部", systemImage: "square.grid.2x2", scope: .all)
                libraryScopeButton(title: "收藏", systemImage: "star.fill", scope: .favorites)

                ForEach(viewModel.mediaCollections) { collection in
                    libraryScopeButton(
                        title: collection.name,
                        systemImage: "folder.fill",
                        scope: .collection(collection.id)
                    )
                }

                Button {
                    isShowingCollectionManager = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("管理收藏夹")
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func libraryScopeButton(
        title: String,
        systemImage: String,
        scope: MediaLibraryScope
    ) -> some View {
        Button {
            withAnimation(.snappy) {
                mediaLibraryScope = scope
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(mediaLibraryScope == scope ? Color.white : Color.primary)
                .background(
                    mediaLibraryScope == scope ? Brand.accent : Color.primary.opacity(0.055),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mediaLibraryScope == scope ? .isSelected : [])
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("保存方式", selection: $inputMode) {
                Label("链接", systemImage: "link")
                    .tag(SaveInputMode.link)
                Label("账号", systemImage: "person.crop.square")
                    .tag(SaveInputMode.profile)
            }
            .pickerStyle(.segmented)

            instagramSessionRow

            if inputMode == .link {
                linkInput
            } else {
                profileInput
            }
        }
        .padding(20)
        .surfaceCard(radius: 26)
        .animation(.snappy, value: inputMode)
    }

    private var instagramSessionRow: some View {
        Button {
            viewModel.showInstagramLogin()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: viewModel.hasInstagramSession ? "checkmark.shield.fill" : "person.badge.key")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(viewModel.hasInstagramSession ? Brand.success : Brand.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.hasInstagramSession ? "Instagram 已连接" : "连接 Instagram")
                        .font(.subheadline.weight(.semibold))

                    Text(instagramSessionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var instagramSessionSubtitle: String {
        switch viewModel.instagramSessionState {
        case let .connected(username):
            if let username, !username.isEmpty {
                return "已登录 @\(username)"
            }
            return "可以读取当前账号有权访问的内容"
        case .expired:
            return "登录已过期，请重新连接"
        case .disconnected:
            return "账号获取和快拍需要登录"
        }
    }

    private var linkInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("内容链接")
                    .font(.headline)

                Text("支持 Instagram 帖子、Reel、快拍和媒体直链")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .padding(.top, 3)

                TextField("粘贴链接…", text: $viewModel.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(2...4)
                    .font(.body)
            }
            .padding(16)
            .frame(minHeight: 58, alignment: .top)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let previewError = viewModel.previewError {
                Label(previewError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.danger)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.pasteFromClipboard()
                        isInputFocused = true
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 86, height: 48)
                    }
                    .buttonStyle(.glass)

                    Button {
                        isInputFocused = false
                        viewModel.start()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isPreparingPreview {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                            Text(viewModel.isPreparingPreview ? "正在解析" : "解析并保存")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.accent)
                    .disabled(!viewModel.canStart)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var profileInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("指定账号")
                    .font(.headline)

                Text("获取最新帖子、Reels，以及当前仍有效的快拍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("@")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.accent)

                TextField("用户名", text: $viewModel.profileUsername)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.fetchLatestProfilePosts()
                    }

                Button {
                    viewModel.toggleCurrentProfileFavorite()
                } label: {
                    Image(systemName: viewModel.isCurrentProfileFavorite ? "star.fill" : "star")
                        .foregroundStyle(viewModel.isCurrentProfileFavorite ? Brand.favorite : Brand.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(viewModel.isCurrentProfileFavorite ? "取消收藏账号" : "收藏账号")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !viewModel.favoriteProfiles.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(viewModel.favoriteProfiles) { favorite in
                            Button {
                                isInputFocused = false
                                viewModel.selectFavoriteProfile(favorite)
                            } label: {
                                Label("@\(favorite.username)", systemImage: "star.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Brand.accent.opacity(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("移除收藏", systemImage: "star.slash", role: .destructive) {
                                    viewModel.removeFavoriteProfile(favorite)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if viewModel.lastProfileNewContentCount > 0 {
                Label("相比上次新增 \(viewModel.lastProfileNewContentCount) 项内容", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.accent)
            }

            if let profileError = viewModel.profileError {
                Label(profileError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.danger)
            }

            Button {
                isInputFocused = false
                profileContentFilter = .post
                viewModel.fetchLatestProfilePosts()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingProfile {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }

                    Text(viewModel.isLoadingProfile ? "正在获取" : "获取主页内容")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.accent)
            .disabled(!viewModel.canFetchProfile)
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    @ViewBuilder
    private var profilePostsSection: some View {
        if inputMode == .profile, !viewModel.profilePosts.isEmpty {
            let visiblePosts = profilePosts(for: profileContentFilter)
            let visibleIDs = Set(visiblePosts.map(\.id))
            let allVisibleSelected = !visibleIDs.isEmpty && visibleIDs.isSubset(of: viewModel.selectedProfilePostIDs)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择要保存的内容")
                        .font(.title3.weight(.bold))

                    Text("帖子与 Reels 分开显示，选择后可一次保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("内容类型", selection: $profileContentFilter) {
                    Text("帖子  \(viewModel.profileRegularPosts.count)")
                        .tag(ProfileContentFilter.post)
                    Text("Reels  \(viewModel.profileReels.count)")
                        .tag(ProfileContentFilter.reel)
                    Text("快拍  \(viewModel.profileStories.count)")
                        .tag(ProfileContentFilter.story)
                }
                .pickerStyle(.segmented)

                HStack {
                    Label(
                        profileContentFilter.title,
                        systemImage: profileContentFilter.iconName
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button(allVisibleSelected ? "取消本栏" : "全选本栏") {
                        viewModel.toggleAllProfilePosts(in: visiblePosts)
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(visiblePosts.isEmpty)
                }

                if visiblePosts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: profileContentFilter.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Text(profileContentFilter.emptyTitle)
                            .font(.subheadline.weight(.semibold))

                        Text(profileContentFilter.emptyDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(visiblePosts) { post in
                            ProfilePostTile(
                                post: post,
                                isSelected: viewModel.selectedProfilePostIDs.contains(post.id)
                            ) {
                                viewModel.toggleProfilePost(post)
                            }
                        }
                    }
                }

                Button {
                    viewModel.saveSelectedProfilePosts()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                        Text("加入队列（\(viewModel.selectedProfilePostIDs.count)）")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
                .disabled(!viewModel.canSaveSelectedProfilePosts)
            }
            .padding(20)
            .surfaceCard(radius: 26)
            .animation(.snappy, value: profileContentFilter)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func profilePosts(for filter: ProfileContentFilter) -> [InstagramProfilePost] {
        switch filter {
        case .post:
            viewModel.profileRegularPosts
        case .reel:
            viewModel.profileReels
        case .story:
            viewModel.profileStories
        }
    }

    @ViewBuilder
    private var taskQueueSection: some View {
        if let currentJob = prioritizedJobs.first {
            let taskCount = prioritizedJobs.count

            SaveQueueProgressView(
                job: currentJob,
                queueCount: taskCount,
                cancelTitle: currentJob.batchID == nil ? "取消" : "取消全部",
                onRetry: { viewModel.retry(currentJob) },
                onForceSave: { viewModel.retry(currentJob, allowDuplicate: true) },
                onCancel: {
                    if currentJob.batchID == nil {
                        viewModel.cancel(currentJob)
                    } else {
                        viewModel.cancelBatch(containing: currentJob)
                    }
                },
                onRemove: { viewModel.remove(currentJob) }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var prioritizedJobs: [SaveJob] {
        viewModel.jobs.sorted { lhs, rhs in
            let leftPriority = jobPriority(lhs)
            let rightPriority = jobPriority(rhs)
            if leftPriority == rightPriority {
                return lhs.createdAt < rhs.createdAt
            }
            return leftPriority < rightPriority
        }
    }

    private func jobPriority(_ job: SaveJob) -> Int {
        if job.status.isRunning { return 0 }
        if job.status == .queued { return 1 }
        switch job.status {
        case .failed, .partiallySaved, .duplicate: return 2
        case .cancelled: return 3
        case .saved, .idle: return 4
        case .queued, .resolving, .downloading, .saving, .cancelling: return 0
        }
    }

}

private enum RecentContentFilter: String, CaseIterable, Identifiable {
    case all
    case post
    case reel
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .post: "帖子"
        case .reel: "Reels"
        case .story: "快拍"
        }
    }

    func matches(_ kind: InstagramContentKind) -> Bool {
        switch self {
        case .all: true
        case .post: kind == .post || kind == .direct || kind == .unknown
        case .reel: kind == .reel
        case .story: kind == .story
        }
    }
}

private enum MediaLibraryScope: Hashable {
    case all
    case favorites
    case collection(UUID)
}

private struct RecentSaveGroup: Identifiable {
    let title: String
    let saves: [RecentSave]
    var id: String { title }
}

private struct MediaPreviewView: View {
    let resolution: MediaResolution
    let selectedAssetIDs: Set<UUID>
    let onToggle: (MediaAsset) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolution.username.map { "@\($0)" } ?? resolution.sourceURL.host(percentEncoded: false) ?? "Instagram")
                            .font(.title3.weight(.bold))
                        Text("已识别 \(resolution.assets.count) 项，选择要保存的内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(resolution.assets) { asset in
                            PreviewAssetTile(
                                asset: asset,
                                isSelected: selectedAssetIDs.contains(asset.id)
                            ) {
                                onToggle(asset)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("保存预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onConfirm) {
                    Label("保存已选（\(selectedAssetIDs.count)）", systemImage: "arrow.down.to.line")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
                .disabled(selectedAssetIDs.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

private struct PreviewAssetTile: View {
    let asset: MediaAsset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                if asset.kind == .image {
                    AsyncImage(url: asset.sourceURL) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    Brand.mediaSurface
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(isSelected ? Brand.accent : .white)
                            .shadow(radius: 3)
                    }
                    Spacer()
                    HStack {
                        Label(asset.kind == .video ? "视频" : "图片", systemImage: asset.kind == .video ? "video.fill" : "photo.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                    }
                }
                .padding(9)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsView: View {
    let sessionState: InstagramSessionState
    let isWorking: Bool
    let onLogin: () -> Void
    let onLogout: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.dedicatedAlbumKey) private var usesDedicatedAlbum = false
    @AppStorage(AppPreferences.previewBeforeSavingKey) private var previewsBeforeSaving = true
    @AppStorage(AppPreferences.duplicateProtectionKey) private var protectsAgainstDuplicates = true
    @AppStorage(AppPreferences.cellularDownloadsKey) private var allowsCellularDownloads = true
    @AppStorage(AppPreferences.completionNotificationsKey) private var completionNotifications = true

    var body: some View {
        NavigationStack {
            Form {
                Section("保存流程") {
                    Toggle("保存链接前先预览", isOn: $previewsBeforeSaving)
                    Toggle("提醒重复保存", isOn: $protectsAgainstDuplicates)
                    Toggle("完成后通知", isOn: $completionNotifications)
                        .onChange(of: completionNotifications) { _, enabled in
                            if enabled {
                                Task { await NotificationService.requestAuthorizationIfNeeded() }
                            }
                        }
                }

                Section("保存位置") {
                    Toggle("整理到“IGSave”相册", isOn: $usesDedicatedAlbum)
                    Text(usesDedicatedAlbum ? "新保存的内容会同时加入 IGSave 系统相册。" : "内容直接添加到系统照片图库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("网络") {
                    Toggle("允许蜂窝网络下载", isOn: $allowsCellularDownloads)
                    if !allowsCellularDownloads {
                        Text("使用移动数据时任务会等待 Wi‑Fi，切换网络后会自动继续。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Instagram 账号") {
                    LabeledContent("状态", value: sessionDescription)
                    if sessionState.isConnected {
                        Button("退出并清除登录数据", role: .destructive, action: onLogout)
                    } else {
                        Button("连接 Instagram", action: onLogin)
                    }
                }

                Section("系统权限") {
                    Button("打开 IGSave 系统设置", action: onOpenSettings)
                    Text("如果相册权限曾被拒绝，可在这里重新开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与支持") {
                    NavigationLink {
                        DiagnosticsView(isWorking: isWorking)
                    } label: {
                        LabeledContent("诊断与隐私", value: AppRuntimeInfo.versionDescription)
                    }
                    Text("诊断记录只保存在本机，不会自动上传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("支持内容") {
                    Label("帖子与轮播帖子", systemImage: "rectangle.stack")
                    Label("Reels 短视频", systemImage: "play.rectangle")
                    Label("当前可访问的快拍", systemImage: "circle.dashed")
                    Text("内容只会保存到这台设备的系统照片图库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var sessionDescription: String {
        switch sessionState {
        case let .connected(username): username.map { "已连接 @\($0)" } ?? "已连接"
        case .expired: "已过期"
        case .disconnected: "未连接"
        }
    }
}

private struct DiagnosticsView: View {
    let isWorking: Bool

    @State private var entries: [DiagnosticEntry] = []
    @State private var cacheBytes: Int64 = 0
    @State private var isShowingClearConfirmation = false

    var body: some View {
        Form {
            Section("隐私") {
                Label("不包含广告或第三方统计 SDK", systemImage: "hand.raised.fill")
                Label("完整链接、Cookie 与登录信息不会写入诊断", systemImage: "eye.slash.fill")
                Label("诊断数据不会自动离开这台设备", systemImage: "iphone")
                Text("只有在你主动使用“导出诊断报告”并选择接收方后，脱敏报告才会被分享。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("诊断") {
                LabeledContent("本机记录", value: "\(entries.count) 条")

                if entries.isEmpty {
                    Text("目前没有诊断记录。保存失败或部分成功时，这里会保留脱敏原因。")
                        .foregroundStyle(.secondary)
                } else {
                    ShareLink(item: DiagnosticStore.report(for: entries)) {
                        Label("导出诊断报告", systemImage: "square.and.arrow.up")
                    }

                    ForEach(entries.prefix(8)) { entry in
                        DiagnosticEntryRow(entry: entry)
                    }

                    Button("清除诊断记录", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                }
            }

            Section("本机缓存") {
                LabeledContent("已下载缓存", value: formattedCacheSize)
                Button("清理已下载缓存") {
                    MediaDownloader.clearCache()
                    reload()
                }
                .disabled(isWorking || cacheBytes == 0)

                Text(isWorking ? "保存任务运行期间暂不清理，避免影响正在写入相册的文件。" : "缓存仅用于恢复未完成任务；成功内容已经保存在系统照片图库中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("版本") {
                LabeledContent("IGSave", value: AppRuntimeInfo.versionDescription)
                LabeledContent("系统", value: ProcessInfo.processInfo.operatingSystemVersionString)
            }
        }
        .navigationTitle("诊断与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog("清除所有本机诊断记录？", isPresented: $isShowingClearConfirmation) {
            Button("清除记录", role: .destructive) {
                DiagnosticStore.clear()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不会影响保存记录和系统相册内容。")
        }
    }

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
    }

    private func reload() {
        entries = DiagnosticStore.entries()
        cacheBytes = MediaDownloader.cacheUsageBytes()
    }
}

private struct DiagnosticEntryRow: View {
    let entry: DiagnosticEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.outcome == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(entry.outcome == .success ? Brand.success : Brand.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.category?.title ?? operationTitle)
                    .font(.subheadline.weight(.semibold))
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let code = entry.code {
                    Text(code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var operationTitle: String {
        switch entry.operation {
        case "save": "保存完成"
        case "preview": "链接预览"
        case "profile": "账号获取"
        default: "应用事件"
        }
    }
}

private enum AppTab: Hashable {
    case save
    case recents
}

private enum SaveInputMode: Hashable {
    case link
    case profile
}

private enum ProfileContentFilter: Hashable {
    case post
    case reel
    case story

    var title: String {
        switch self {
        case .post:
            "最新帖子"
        case .reel:
            "最新 Reels"
        case .story:
            "当前快拍"
        }
    }

    var iconName: String {
        switch self {
        case .post:
            "rectangle.stack"
        case .reel:
            "play.rectangle"
        case .story:
            "circle.dashed"
        }
    }

    var emptyTitle: String {
        switch self {
        case .post:
            "暂无帖子"
        case .reel:
            "暂无 Reels"
        case .story:
            "暂无快拍"
        }
    }

    var emptyDescription: String {
        switch self {
        case .post:
            "这个账号最近没有可访问的帖子。"
        case .reel:
            "这个账号最近没有可访问的短视频。"
        case .story:
            "快拍可能已经过期，或当前账号无权查看。"
        }
    }
}

private enum Brand {
    static let accent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.40, green: 0.47, blue: 0.52, alpha: 1)
        }
        return UIColor(red: 0.31, green: 0.37, blue: 0.41, alpha: 1)
    })
    static let mediaSurface = Color(red: 0.25, green: 0.29, blue: 0.32)
    static let success = Color(red: 0.34, green: 0.49, blue: 0.39)
    static let warning = Color(red: 0.62, green: 0.49, blue: 0.30)
    static let danger = Color(red: 0.61, green: 0.31, blue: 0.33)
    static let favorite = Color(red: 0.62, green: 0.52, blue: 0.31)
}

private struct AppBackdrop: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

private struct ProfilePostTile: View {
    let post: InstagramProfilePost
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                ZStack {
                    placeholder

                    if let thumbnailURL = post.thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            if case let .success(image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    }

                    VStack {
                        HStack(alignment: .top) {
                            Label(post.contentKind.title, systemImage: post.contentKind.iconName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.46), in: Capsule())

                            Spacer()

                            Image(systemName: isSelected ? "checkmark" : "circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.95))
                                .frame(width: 28, height: 28)
                                .background(isSelected ? Brand.accent : .black.opacity(0.34), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.88), lineWidth: 1.5)
                                }
                        }

                        Spacer()

                        if isSelected {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                Text("已选择")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Brand.accent.opacity(0.92), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(post.contentKind.title)，\(isSelected ? "已选择" : "未选择")")
    }

    private var placeholder: some View {
        ZStack {
            Brand.mediaSurface

            Image(systemName: post.contentKind.iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct RecentSaveRow: View {
    let save: RecentSave
    let collections: [MediaCollection]
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onSaveAgain: () -> Void
    let onDelete: () -> Void
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 15) {
            RecentPreview(filename: save.previewFilename, contentKind: save.contentKind)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(save.username)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(relativeTime)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 7) {
                    Label(save.contentKind.title, systemImage: save.contentKind.iconName)

                    Text("·")

                    Text("\(save.itemCount) 个文件")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                if !metadataLabels.isEmpty {
                    Text(metadataLabels.joined(separator: "  ·  "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Brand.accent)
                        .lineLimit(1)
                }
            }

            Button(action: onToggleFavorite) {
                Image(systemName: save.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(save.isFavorite ? Brand.favorite : Color.secondary)
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(save.isFavorite ? "取消收藏" : "加入收藏")

            Menu {
                Button(save.isFavorite ? "取消收藏" : "加入收藏", systemImage: save.isFavorite ? "star.slash" : "star", action: onToggleFavorite)
                Button("打开原链接", systemImage: "safari", action: onOpen)
                Button("复制链接", systemImage: "doc.on.doc", action: onCopy)
                Button("再次保存", systemImage: "arrow.clockwise", action: onSaveAgain)
                Divider()
                Button("删除记录", systemImage: "trash", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 44)
            }
        }
        .padding(13)
        .surfaceCard(radius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onSelect)
        .confirmationDialog(
            "删除这条媒体记录？",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("删除记录", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("系统照片不会被删除，但这条记录的收藏夹、标签和备注会一并移除。")
        }
    }

    private var metadataLabels: [String] {
        let collectionNames = collections
            .filter { save.collectionIDs.contains($0.id) }
            .prefix(1)
            .map(\.name)
        let tags = save.tags.prefix(2).map { "#\($0)" }
        let noteLabel = save.note?.isEmpty == false ? ["有备注"] : []
        return collectionNames + tags + noteLabel
    }

    private var relativeTime: String {
        let calendar = Calendar.current
        if calendar.isDateInYesterday(save.savedAt) {
            return "昨天"
        }
        if !calendar.isDateInToday(save.savedAt) {
            let components = calendar.dateComponents([.month, .day], from: save.savedAt)
            return "\(components.month ?? 0)月\(components.day ?? 0)日"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: save.savedAt, relativeTo: Date())
    }
}

private struct RecentSaveDetailView: View {
    let save: RecentSave
    let collections: [MediaCollection]
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onUpdateMetadata: (Bool, [UUID], [String], String?) -> Void
    let onSaveAgain: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isFavorite: Bool
    @State private var collectionIDs: [UUID]
    @State private var tags: [String]
    @State private var note: String?
    @State private var isEditingMetadata = false
    @State private var isShowingDeleteConfirmation = false

    init(
        save: RecentSave,
        collections: [MediaCollection],
        onOpen: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onUpdateMetadata: @escaping (Bool, [UUID], [String], String?) -> Void,
        onSaveAgain: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.save = save
        self.collections = collections
        self.onOpen = onOpen
        self.onCopy = onCopy
        self.onUpdateMetadata = onUpdateMetadata
        self.onSaveAgain = onSaveAgain
        self.onDelete = onDelete
        _isFavorite = State(initialValue: save.isFavorite)
        _collectionIDs = State(initialValue: save.collectionIDs)
        _tags = State(initialValue: save.tags)
        _note = State(initialValue: save.note)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 20) {
                        RecentDetailPreview(
                            filename: save.previewFilename,
                            contentKind: save.contentKind
                        )

                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(save.username)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(1)
                                Text("\(save.contentKind.title) · \(save.itemCount) 个文件")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 8) {
                                Button {
                                    isFavorite.toggle()
                                    persistMetadata()
                                } label: {
                                    Image(systemName: isFavorite ? "star.fill" : "star")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(isFavorite ? Brand.favorite : Brand.accent)
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel(isFavorite ? "取消收藏" : "加入收藏")

                                Text(detailDate)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        Button {
                            isEditingMetadata = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.title3)
                                    .foregroundStyle(Brand.accent)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("整理信息")
                                        .font(.subheadline.weight(.semibold))
                                    Text(metadataSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .surfaceCard(radius: 20)
                        }
                        .buttonStyle(.plain)

                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                detailAction(
                                    title: "再次保存",
                                    systemImage: "arrow.clockwise",
                                    isPrimary: true,
                                    action: onSaveAgain
                                )
                                detailAction(
                                    title: "Instagram",
                                    systemImage: "arrow.up.right",
                                    action: onOpen
                                )
                                detailAction(
                                    title: "复制链接",
                                    systemImage: "doc.on.doc",
                                    action: onCopy
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("保存详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("编辑整理信息", systemImage: "tag") {
                            isEditingMetadata = true
                        }
                        Button("删除记录", systemImage: "trash", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
            .sheet(isPresented: $isEditingMetadata) {
                LibraryMetadataEditor(
                    collections: collections,
                    initialCollectionIDs: collectionIDs,
                    initialTags: tags,
                    initialNote: note
                ) { updatedCollectionIDs, updatedTags, updatedNote in
                    collectionIDs = updatedCollectionIDs
                    tags = updatedTags
                    note = updatedNote
                    persistMetadata()
                }
            }
            .confirmationDialog(
                "删除这条媒体记录？",
                isPresented: $isShowingDeleteConfirmation
            ) {
                Button("删除记录", role: .destructive, action: onDelete)
                Button("取消", role: .cancel) {}
            } message: {
                Text("系统照片不会被删除，但这条记录的收藏夹、标签和备注会一并移除。")
            }
        }
    }

    private var metadataSummary: String {
        let collectionNames = collections
            .filter { collectionIDs.contains($0.id) }
            .map(\.name)
        let tagNames = tags.map { "#\($0)" }
        let values = collectionNames + tagNames

        if !values.isEmpty {
            return values.joined(separator: " · ")
        }
        if let note, !note.isEmpty {
            return note
        }
        return "添加收藏夹、标签或备注"
    }

    private func persistMetadata() {
        onUpdateMetadata(isFavorite, collectionIDs, tags, note)
    }

    @ViewBuilder
    private func detailAction(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
        }

        if isPrimary {
            button
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var detailDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: save.savedAt)
    }
}

private struct LibraryMetadataEditor: View {
    let collections: [MediaCollection]
    let onSave: ([UUID], [String], String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCollectionIDs: Set<UUID>
    @State private var tagText: String
    @State private var noteText: String

    init(
        collections: [MediaCollection],
        initialCollectionIDs: [UUID],
        initialTags: [String],
        initialNote: String?,
        onSave: @escaping ([UUID], [String], String?) -> Void
    ) {
        self.collections = collections
        self.onSave = onSave
        _selectedCollectionIDs = State(initialValue: Set(initialCollectionIDs))
        _tagText = State(initialValue: initialTags.joined(separator: "，"))
        _noteText = State(initialValue: initialNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("收藏夹") {
                    if collections.isEmpty {
                        Text("还没有收藏夹，可在媒体库右上角菜单中创建。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collections) { collection in
                            Button {
                                if selectedCollectionIDs.contains(collection.id) {
                                    selectedCollectionIDs.remove(collection.id)
                                } else {
                                    selectedCollectionIDs.insert(collection.id)
                                }
                            } label: {
                                HStack {
                                    Label(collection.name, systemImage: "folder.fill")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedCollectionIDs.contains(collection.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Brand.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("标签") {
                    TextField("旅行，美食，灵感", text: $tagText, axis: .vertical)
                        .lineLimit(2...4)
                    Text("使用空格、逗号或 # 分隔，最多保留 10 个标签。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("备注") {
                    TextField("写下保存它的原因或后续想法…", text: $noteText, axis: .vertical)
                        .lineLimit(3...7)
                    Text("备注仅保存在本机，最多 300 个字符。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("整理媒体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let orderedCollectionIDs = collections
                            .map(\.id)
                            .filter { selectedCollectionIDs.contains($0) }
                        onSave(orderedCollectionIDs, parsedTags, normalizedNote)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedTags: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",，#"))
        return RecentSaveStore.normalizedTags(
            tagText.components(separatedBy: separators)
        )
    }

    private var normalizedNote: String? {
        let value = String(noteText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        return value.isEmpty ? nil : value
    }
}

private struct CollectionManagerView: View {
    let itemCount: (MediaCollection) -> Int
    let onCreate: (String) -> [MediaCollection]
    let onRename: (MediaCollection, String) -> [MediaCollection]
    let onDelete: (MediaCollection) -> [MediaCollection]

    @Environment(\.dismiss) private var dismiss
    @State private var collections: [MediaCollection]
    @State private var newCollectionName = ""
    @State private var editingCollection: MediaCollection?
    @State private var editedName = ""
    @State private var isShowingRenameAlert = false
    @State private var deletingCollection: MediaCollection?
    @State private var isShowingDeleteDialog = false

    init(
        collections: [MediaCollection],
        itemCount: @escaping (MediaCollection) -> Int,
        onCreate: @escaping (String) -> [MediaCollection],
        onRename: @escaping (MediaCollection, String) -> [MediaCollection],
        onDelete: @escaping (MediaCollection) -> [MediaCollection]
    ) {
        _collections = State(initialValue: collections)
        self.itemCount = itemCount
        self.onCreate = onCreate
        self.onRename = onRename
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("新建收藏夹") {
                    HStack {
                        TextField("例如：旅行灵感", text: $newCollectionName)
                            .submitLabel(.done)
                            .onSubmit(createCollection)

                        Button("添加", action: createCollection)
                            .disabled(!canCreateCollection)
                    }
                    Text(newCollectionValidationMessage ?? "收藏夹用于按主题整理内容，不会修改系统照片图库。")
                        .font(.caption)
                        .foregroundStyle(newCollectionValidationMessage == nil ? Color.secondary : Brand.danger)
                }

                Section("我的收藏夹") {
                    if collections.isEmpty {
                        Text("还没有收藏夹。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collections) { collection in
                            CollectionManagerRow(
                                collection: collection,
                                itemCount: itemCount(collection),
                                onRename: {
                                    editedName = collection.name
                                    editingCollection = collection
                                    isShowingRenameAlert = true
                                },
                                onDelete: {
                                    deletingCollection = collection
                                    isShowingDeleteDialog = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("管理收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重命名收藏夹", isPresented: $isShowingRenameAlert, presenting: editingCollection) { collection in
                TextField("收藏夹名称", text: $editedName)
                Button("取消", role: .cancel) {
                    editingCollection = nil
                }
                Button("保存") {
                    collections = onRename(collection, editedName)
                    editingCollection = nil
                }
                .disabled(!canRename(collection))
            } message: { collection in
                Text(renameValidationMessage(for: collection) ?? "名称最多 30 个字符，且不能与现有收藏夹重名。")
            }
            .confirmationDialog(
                "删除“\(deletingCollection?.name ?? "")”？",
                isPresented: $isShowingDeleteDialog,
                presenting: deletingCollection
            ) { collection in
                Button("删除收藏夹", role: .destructive) {
                    collections = onDelete(collection)
                    deletingCollection = nil
                }
                Button("取消", role: .cancel) {
                    deletingCollection = nil
                }
            } message: { _ in
                Text("收藏夹中的媒体记录会保留，只移除分类关系。")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createCollection() {
        let name = MediaCollectionStore.normalizedName(newCollectionName)
        guard canCreateCollection else { return }
        collections = onCreate(name)
        newCollectionName = ""
    }

    private var canCreateCollection: Bool {
        !MediaCollectionStore.normalizedName(newCollectionName).isEmpty &&
            newCollectionValidationMessage == nil
    }

    private var newCollectionValidationMessage: String? {
        let trimmedName = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = MediaCollectionStore.normalizedName(newCollectionName)
        if collections.count >= MediaCollectionStore.maximumCount {
            return "最多可创建 \(MediaCollectionStore.maximumCount) 个收藏夹。"
        }
        if trimmedName.count > 30 {
            return "收藏夹名称最多 30 个字符。"
        }
        if name.isEmpty {
            return newCollectionName.isEmpty ? nil : "请输入收藏夹名称。"
        }
        if collections.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "已经有同名收藏夹。"
        }
        return nil
    }

    private func canRename(_ collection: MediaCollection) -> Bool {
        renameValidationMessage(for: collection) == nil
    }

    private func renameValidationMessage(for collection: MediaCollection) -> String? {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = MediaCollectionStore.normalizedName(editedName)
        if trimmedName.count > 30 {
            return "收藏夹名称最多 30 个字符。"
        }
        if name.isEmpty {
            return "请输入收藏夹名称。"
        }
        if collections.contains(where: {
            $0.id != collection.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "已经有同名收藏夹。"
        }
        return nil
    }
}

private struct CollectionManagerRow: View {
    let collection: MediaCollection
    let itemCount: Int
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                Text("\(itemCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("重命名", systemImage: "pencil", action: onRename)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 34, height: 40)
            }
        }
    }
}

private struct RecentDetailPreview: View {
    let filename: String?
    let contentKind: InstagramContentKind

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.94))

            if let url = RecentSaveStore.previewURL(for: filename) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }

            if filename != nil {
                Text(contentKind.previewLabel)
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
    }

    private var fallback: some View {
        ZStack {
            Brand.mediaSurface
            Text(contentKind.previewLabel)
                .font(.title3.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SaveQueueProgressView: View {
    let job: SaveJob
    let queueCount: Int
    let cancelTitle: String
    let onRetry: () -> Void
    let onForceSave: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(job.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(job.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(job.status.tint)
                    .lineLimit(1)
            }

            ProgressView(value: job.status.progressFraction)
                .progressViewStyle(.linear)
                .tint(job.status.tint)
                .animation(.smooth, value: job.status.progressFraction)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if queueCount > 1 {
                        Text("队列中还有 \(queueCount - 1) 项")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                actionButtons
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var actionButtons: some View {
        GlassEffectContainer(spacing: 7) {
            HStack(spacing: 7) {
                switch job.status {
                case .queued, .idle, .resolving, .downloading, .saving:
                    Button(cancelTitle, role: .destructive, action: onCancel)
                        .buttonStyle(.glass)
                case .cancelling:
                    EmptyView()
                case .partiallySaved:
                    Button("重试失败项", action: onRetry)
                        .buttonStyle(.glassProminent)
                        .tint(Brand.accent)
                    Button("移除", action: onRemove)
                        .buttonStyle(.glass)
                case .failed, .cancelled:
                    Button("重试", action: onRetry)
                        .buttonStyle(.glassProminent)
                        .tint(Brand.accent)
                    Button("移除", action: onRemove)
                        .buttonStyle(.glass)
                case .duplicate:
                    Button("保存", action: onForceSave)
                        .buttonStyle(.glassProminent)
                        .tint(Brand.accent)
                    Button("移除", action: onRemove)
                        .buttonStyle(.glass)
                case .saved:
                    EmptyView()
                }
            }
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
    }
}

private struct RecentPreview: View {
    let filename: String?
    let contentKind: InstagramContentKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Brand.mediaSurface)

            if let url = RecentSaveStore.previewURL(for: filename) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 0.8)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: contentKind == .reel || contentKind == .story ? "play.fill" : "photo")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(.white)
    }
}

private struct SurfaceCardModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
    }
}

private extension View {
    func surfaceCard(radius: CGFloat) -> some View {
        modifier(SurfaceCardModifier(radius: radius))
    }

    @ViewBuilder
    func recentSearchable(enabled: Bool, text: Binding<String>) -> some View {
        if enabled {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索账号、标签或备注"
            )
        } else {
            self
        }
    }
}

private extension SaveStatus {
    var tint: Color {
        switch self {
        case .saved:
            Brand.success
        case .partiallySaved:
            Brand.warning
        case .duplicate:
            Brand.warning
        case .failed:
            Brand.danger
        case .cancelled:
            .secondary
        case .idle, .queued:
            .secondary
        case .resolving, .downloading, .saving:
            Brand.accent
        case .cancelling:
            .secondary
        }
    }

    var progressFraction: Double {
        switch self {
        case .idle, .queued:
            0.03
        case .resolving:
            0.1
        case let .downloading(current, total):
            0.1 + (Double(max(current - 1, 0)) / Double(max(total, 1))) * 0.8
        case let .saving(current, total):
            0.1 + ((Double(current) - 0.5) / Double(max(total, 1))) * 0.8
        case .saved, .partiallySaved, .duplicate, .failed:
            1
        case .cancelling:
            0.95
        case .cancelled:
            0
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "等待开始"
        case .queued:
            "已加入队列"
        case .resolving:
            "正在识别链接中的媒体"
        case let .downloading(current, total):
            "正在下载第 \(current) 项，共 \(total) 项"
        case let .saving(current, total):
            "正在写入相册，第 \(current) 项，共 \(total) 项"
        case .cancelling:
            "正在安全停止当前任务"
        case let .saved(count):
            "\(count) 个文件已写入系统相册"
        case let .partiallySaved(saved, failed, message):
            "已保存 \(saved) 项，\(failed) 项失败。\(message)"
        case let .duplicate(previousSavedAt):
            "上次保存于 \(previousSavedAt.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(message):
            message
        case .cancelled:
            "可以重新加入队列"
        }
    }
}

private extension SaveJob {
    var displayTitle: String {
        let kindTitle = contentKind?.title ?? inferredContentKind.title
        if let username, !username.isEmpty {
            return "@\(username) · \(kindTitle)"
        }
        if let identity = instagramIdentity {
            return "\(identity) · \(kindTitle)"
        }
        return kindTitle
    }

    private var instagramIdentity: String? {
        let components = sourceURL?.pathComponents.filter { $0 != "/" } ?? []

        if let storyIndex = components.firstIndex(of: "stories"),
           components.indices.contains(storyIndex + 1) {
            return "@\(components[storyIndex + 1])"
        }

        for route in ["p", "reel", "tv"] {
            if let routeIndex = components.firstIndex(of: route),
               components.indices.contains(routeIndex + 1) {
                return components[routeIndex + 1]
            }
        }

        return nil
    }

    private var inferredContentKind: InstagramContentKind {
        let components = sourceURL?.pathComponents.filter { $0 != "/" } ?? []
        if components.contains("stories") { return .story }
        if components.contains("reel") || components.contains("tv") { return .reel }
        if components.contains("p") { return .post }
        return .unknown
    }

    private var sourceURL: URL? {
        if let url = URL(string: input), url.scheme != nil {
            return url
        }

        return input
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { URL(string: String($0)) }
            .first { $0.scheme != nil }
    }
}

private extension InstagramContentKind {
    var title: String {
        switch self {
        case .direct:
            "媒体直链"
        case .post:
            "帖子"
        case .reel:
            "Reel"
        case .story:
            "快拍"
        case .unknown:
            "媒体"
        }
    }

    var iconName: String {
        switch self {
        case .direct:
            "link"
        case .post:
            "rectangle.stack"
        case .reel:
            "play.rectangle"
        case .story:
            "circle.dashed"
        case .unknown:
            "photo"
        }
    }

    var previewLabel: String {
        switch self {
        case .direct:
            "MEDIA"
        case .post:
            "POST"
        case .reel:
            "REEL"
        case .story:
            "STORY"
        case .unknown:
            "IG"
        }
    }
}

#Preview {
    ContentView()
}
