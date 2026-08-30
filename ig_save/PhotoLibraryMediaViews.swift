//
//  PhotoLibraryMediaViews.swift
//  IGSave
//

import AVKit
import Combine
import Photos
import SwiftUI
import UIKit

private enum PhotoLibraryLoadState: Equatable {
    case idle
    case loading
    case ready
    case denied
    case unavailable
}

@MainActor
private final class PhotoLibraryAssetsModel: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var state: PhotoLibraryLoadState = .idle

    private let assetIdentifiers: [String]

    init(assetIdentifiers: [String]) {
        self.assetIdentifiers = assetIdentifiers
    }

    func load() async {
        guard state == .idle else { return }
        guard !assetIdentifiers.isEmpty else {
            state = .unavailable
            return
        }

        state = .loading
        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        guard authorization == .authorized || authorization == .limited else {
            state = .denied
            return
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            assetsByIdentifier[asset.localIdentifier] = asset
        }
        assets = assetIdentifiers.compactMap { assetsByIdentifier[$0] }
        state = assets.isEmpty ? .unavailable : .ready
    }
}

struct PhotoLibraryDetailPreview: View {
    let assetIdentifiers: [String]
    let fallbackFilename: String?
    let contentKind: InstagramContentKind
    let tint: Color
    let onOpen: () -> Void

    @StateObject private var model: PhotoLibraryAssetsModel

    init(
        assetIdentifiers: [String],
        fallbackFilename: String?,
        contentKind: InstagramContentKind,
        tint: Color,
        onOpen: @escaping () -> Void
    ) {
        self.assetIdentifiers = assetIdentifiers
        self.fallbackFilename = fallbackFilename
        self.contentKind = contentKind
        self.tint = tint
        self.onOpen = onOpen
        _model = StateObject(wrappedValue: PhotoLibraryAssetsModel(assetIdentifiers: assetIdentifiers))
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Color.black.opacity(0.96)

                if let asset = model.assets.first {
                    PhotoLibraryAssetImage(asset: asset, contentMode: .fit)
                } else {
                    fallback
                }

                VStack {
                    HStack {
                        Text(contentKind.previewLabel)
                            .font(.caption2.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: Capsule())

                        Spacer()

                        if assetIdentifiers.count > 1 {
                            Label("\(assetIdentifiers.count)", systemImage: "square.on.square")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.45), in: Capsule())
                        }
                    }

                    Spacer()

                    HStack {
                        Spacer()
                        Label(previewActionTitle, systemImage: previewActionIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(tint.opacity(0.94), in: Capsule())
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .task { await model.load() }
        .accessibilityLabel("查看已保存的\(contentKind.title)")
        .accessibilityHint("全屏查看图片或播放视频")
    }

    private var fallback: some View {
        Group {
            if let url = RecentSaveStore.previewURL(for: fallbackFilename) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fallbackIcon: some View {
        ZStack {
            Color(red: 0.25, green: 0.29, blue: 0.32)
            Image(systemName: contentKind == .post ? "photo" : "play.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var previewActionTitle: String {
        switch model.state {
        case .loading:
            "正在读取"
        case .denied:
            "允许照片访问"
        case .unavailable where assetIdentifiers.isEmpty:
            "旧记录预览"
        default:
            contentKind == .post ? "全屏查看" : "播放内容"
        }
    }

    private var previewActionIcon: String {
        switch model.state {
        case .loading:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .denied:
            "lock.open"
        case .unavailable where assetIdentifiers.isEmpty:
            "info.circle"
        default:
            contentKind == .post ? "arrow.up.left.and.arrow.down.right" : "play.fill"
        }
    }
}

struct PhotoLibraryMediaViewer: View {
    let assetIdentifiers: [String]
    let fallbackFilename: String?
    let contentKind: InstagramContentKind
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: PhotoLibraryAssetsModel
    @State private var selectedIdentifier: String?

    init(
        assetIdentifiers: [String],
        fallbackFilename: String?,
        contentKind: InstagramContentKind,
        tint: Color
    ) {
        self.assetIdentifiers = assetIdentifiers
        self.fallbackFilename = fallbackFilename
        self.contentKind = contentKind
        self.tint = tint
        _model = StateObject(wrappedValue: PhotoLibraryAssetsModel(assetIdentifiers: assetIdentifiers))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            viewerContent
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .tint(.white)

                Spacer()

                if model.assets.count > 1 {
                    Text(pageCounter)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .glassEffect(.regular, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .task {
            await model.load()
            selectedIdentifier = selectedIdentifier ?? model.assets.first?.localIdentifier
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var viewerContent: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("正在读取系统照片…")
                .tint(.white)
                .foregroundStyle(.white)
        case .ready:
            TabView(selection: $selectedIdentifier) {
                ForEach(model.assets, id: \.localIdentifier) { asset in
                    PhotoLibraryAssetPage(asset: asset)
                        .tag(Optional(asset.localIdentifier))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        case .denied:
            unavailableView(
                title: "需要照片访问权限",
                description: "允许 IGSave 读取已保存的媒体，才能在详情中查看原图和播放视频。",
                buttonTitle: "前往系统设置",
                buttonAction: openSettings
            )
        case .unavailable:
            if assetIdentifiers.isEmpty {
                unavailableView(
                    title: "这是升级前的保存记录",
                    description: "旧记录只保留了缩略图。再次保存后，即可在 IGSave 内查看完整媒体。",
                    buttonTitle: nil,
                    buttonAction: nil
                )
            } else {
                unavailableView(
                    title: "媒体已不可用",
                    description: "对应的系统照片可能已被删除，或不在当前允许访问的照片范围内。",
                    buttonTitle: "检查照片权限",
                    buttonAction: openSettings
                )
            }
        }
    }

    private var pageCounter: String {
        guard
            let selectedIdentifier,
            let index = model.assets.firstIndex(where: { $0.localIdentifier == selectedIdentifier })
        else {
            return "1 / \(max(model.assets.count, 1))"
        }
        return "\(index + 1) / \(model.assets.count)"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    @ViewBuilder
    private func unavailableView(
        title: String,
        description: String,
        buttonTitle: String?,
        buttonAction: (() -> Void)?
    ) -> some View {
        VStack(spacing: 16) {
            if let url = RecentSaveStore.previewURL(for: fallbackFilename) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)

            if let buttonTitle, let buttonAction {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            }
        }
        .padding(24)
    }
}

private struct PhotoLibraryAssetPage: View {
    let asset: PHAsset

    var body: some View {
        Group {
            if asset.mediaType == .video {
                PhotoLibraryVideoView(asset: asset)
            } else {
                PhotoLibraryAssetImage(asset: asset, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PhotoLibraryAssetImage: View {
    let asset: PHAsset
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var requestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear(perform: requestImage)
        .onDisappear(perform: cancelRequest)
    }

    private func requestImage() {
        guard requestID == PHInvalidImageRequestID else { return }
        let targetSize = CGSize(width: 3_000, height: 3_000)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        requestID = PHCachingImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: options
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in
                image = result
            }
        }
    }

    private func cancelRequest() {
        guard requestID != PHInvalidImageRequestID else { return }
        PHCachingImageManager.default().cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}

@MainActor
private final class PhotoLibraryVideoPlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = true
    private var requestID = PHInvalidImageRequestID

    func load(asset: PHAsset) {
        guard requestID == PHInvalidImageRequestID else { return }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        requestID = PHCachingImageManager.default().requestPlayerItem(
            forVideo: asset,
            options: options
        ) { [weak self] playerItem, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                guard let playerItem else { return }
                let player = AVPlayer(playerItem: playerItem)
                self.player = player
                player.play()
            }
        }
    }

    func stop() {
        player?.pause()
        if requestID != PHInvalidImageRequestID {
            PHCachingImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }
}

private struct PhotoLibraryVideoView: View {
    let asset: PHAsset
    @StateObject private var model = PhotoLibraryVideoPlayerModel()

    var body: some View {
        ZStack {
            VideoPlayer(player: model.player)
            if model.isLoading {
                ProgressView("正在准备视频…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .onAppear { model.load(asset: asset) }
        .onDisappear { model.stop() }
    }
}
