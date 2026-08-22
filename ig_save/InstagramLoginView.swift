//
//  InstagramLoginView.swift
//  ig_save
//

import SwiftUI
import WebKit

struct InstagramLoginView: View {
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InstagramLoginWebView(url: InstagramSessionStore.loginURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Instagram 登录")
                .instagramNavigationTitleMode()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onFinish()
                            dismiss()
                        }
                    }
                }
        }
    }
}

#if canImport(UIKit)
private struct InstagramLoginWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
private struct InstagramLoginWebView: View {
    let url: URL

    var body: some View {
        Text("Instagram 登录仅在 iOS 设备上可用。")
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}
#endif

private extension View {
    @ViewBuilder
    func instagramNavigationTitleMode() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
