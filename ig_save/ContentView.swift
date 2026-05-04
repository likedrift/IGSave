//
//  ContentView.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                inputPanel
                historyList
            }
            .padding()
            .navigationTitle("IG Save")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.pasteFromClipboard()
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
    }

    private var inputPanel: some View {
        VStack(spacing: 12) {
            TextField("Instagram 链接或图片/视频直链", text: $viewModel.inputText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(2...5)
                .padding(12)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            Button {
                viewModel.start()
            } label: {
                Label(viewModel.isWorking ? "处理中" : "保存到相册", systemImage: viewModel.isWorking ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStart)
        }
    }

    private var historyList: some View {
        Group {
            if viewModel.jobs.isEmpty {
                ContentUnavailableView("暂无记录", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.jobs) { job in
                    jobRow(job)
                }
                .listStyle(.plain)
            }
        }
    }

    private func jobRow(_ job: SaveJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: job.status))
                    .foregroundStyle(color(for: job.status))
                    .frame(width: 22)

                Text(job.status.title)
                    .font(.headline)
                    .foregroundStyle(color(for: job.status))

                Spacer()

                if job.status.isRunning {
                    ProgressView()
                }
            }

            Text(job.input)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if case let .failed(message) = job.status {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
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
            .accentColor
        }
    }
}

#Preview {
    ContentView()
}
