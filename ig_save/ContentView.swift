//
//  ContentView.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        inputPanel
                        statusPanel
                        recentSavesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.pasteFromClipboard()
                        isInputFocused = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(), in: .rect(cornerRadius: 21))
                    .accessibilityLabel("粘贴链接")
                }
            }
        }
    }

    private var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.20, blue: 0.42).opacity(0.22),
                    Color(red: 0.16, green: 0.78, blue: 0.96).opacity(0.18),
                    Color(red: 1.00, green: 0.74, blue: 0.26).opacity(0.16),
                    Color(red: 0.98, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.54),
                    Color.white.opacity(0.06),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.28, blue: 0.44),
                                Color(red: 1.0, green: 0.70, blue: 0.22),
                                Color(red: 0.15, green: 0.78, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)
            .shadow(color: .pink.opacity(0.22), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("IG Save")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .tracking(0)

                Text("保存公开帖子到本地相册")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var inputPanel: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("新保存", systemImage: "link")
                        .font(.headline)
                    Spacer()
                    if viewModel.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                TextField("粘贴 Instagram 帖子链接或图片/视频直链", text: $viewModel.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(2...4)
                    .font(.body)
                    .padding(14)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }

                HStack(spacing: 12) {
                    Button {
                        viewModel.pasteFromClipboard()
                        isInputFocused = true
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.large)
                    .frame(height: 52)
                    .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(), in: .rect(cornerRadius: 18))

                    Button {
                        isInputFocused = false
                        viewModel.start()
                    } label: {
                        Label(viewModel.isWorking ? "处理中" : "保存", systemImage: viewModel.isWorking ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.20, blue: 0.40),
                                Color(red: 0.99, green: 0.55, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .glassEffect(.regular.tint(.pink.opacity(0.28)).interactive(), in: .rect(cornerRadius: 18))
                    .disabled(!viewModel.canStart)
                    .opacity(viewModel.canStart ? 1 : 0.42)
                }
            }
            .padding(18)
            .liquidPanel(radius: 28, tint: .white.opacity(0.10))
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        if let job = viewModel.jobs.first {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: job.status))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color(for: job.status))
                    .frame(width: 32, height: 32)
                    .background(color(for: job.status).opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.status.title)
                        .font(.subheadline.weight(.semibold))

                    Text(job.input)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if job.status.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(14)
            .liquidPanel(radius: 22, tint: color(for: job.status).opacity(0.08))
        }
    }

    private var recentSavesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近保存")
                    .font(.title2.bold())

                Spacer()

                Text("最近 5 次")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.recentSaves.isEmpty {
                emptyRecentSaves
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.recentSaves) { save in
                        RecentSaveRow(save: save)
                    }
                }
            }
        }
    }

    private var emptyRecentSaves: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("保存成功后会在这里显示")
                .font(.headline)

            Text("包含用户、时间、数量和首张图片预览")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .liquidPanel(radius: 26, tint: .white.opacity(0.08))
    }

    private func iconName(for status: SaveStatus) -> String {
        switch status {
        case .idle:
            "clock"
        case .resolving:
            "magnifyingglass"
        case .downloading:
            "arrow.down.circle"
        case .saving:
            "photo.badge.plus"
        case .saved:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func color(for status: SaveStatus) -> Color {
        switch status {
        case .saved:
            .green
        case .failed:
            .red
        case .idle:
            .secondary
        case .resolving, .downloading, .saving:
            Color(red: 0.98, green: 0.30, blue: 0.46)
        }
    }
}

private struct RecentSaveRow: View {
    let save: RecentSave

    var body: some View {
        HStack(spacing: 14) {
            RecentPreview(filename: save.previewFilename, contentKind: save.contentKind)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(save.username)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(save.savedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(contentTitle, systemImage: contentIcon)
                    Text("\(save.itemCount) 个文件")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .liquidPanel(radius: 24, tint: .white.opacity(0.10))
    }

    private var contentTitle: String {
        switch save.contentKind {
        case .direct:
            "直链"
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

    private var contentIcon: String {
        switch save.contentKind {
        case .direct:
            "link"
        case .post:
            "square.grid.2x2"
        case .reel:
            "play.rectangle"
        case .story:
            "circle.dashed"
        case .unknown:
            "photo"
        }
    }

    private var sourceSummary: String {
        guard let url = URL(string: save.sourceURL) else {
            return save.sourceURL
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if path.isEmpty {
            return url.host(percentEncoded: false) ?? save.sourceURL
        }

        return path
    }
}

private struct RecentPreview: View {
    let filename: String?
    let contentKind: InstagramContentKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.30, blue: 0.46).opacity(0.9),
                            Color(red: 0.14, green: 0.76, blue: 0.95).opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: contentKind == .reel || contentKind == .story ? "play.fill" : "photo")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
    }
}

private struct LiquidPanelModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.23), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 22, y: 10)
    }
}

private extension View {
    func liquidPanel(radius: CGFloat, tint: Color) -> some View {
        modifier(LiquidPanelModifier(radius: radius, tint: tint))
    }
}

#Preview {
    ContentView()
}
