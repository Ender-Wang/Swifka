import SwiftUI

struct UpdateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            switch appState.updateStatus {
            case let .available(release):
                availableContent(release: release, l10n: l10n)
            case let .downloading(progress):
                downloadingContent(progress: progress, l10n: l10n)
            case let .readyToInstall(release, _):
                readyContent(release: release, l10n: l10n)
            case .installing:
                installingContent(l10n: l10n)
            case let .error(error):
                errorContent(error: error, l10n: l10n)
            default:
                EmptyView()
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Update Available

    private func availableContent(release: GitHubRelease, l10n: L10n) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Swifka · \(l10n["updates.available"])")
                        .font(.headline)
                    HStack(spacing: 0) {
                        if let date = release.publishedDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            Text(" · ")
                                .foregroundStyle(.tertiary)
                        }
                        Text("v\(release.version)")
                            .foregroundStyle(.secondary)
                        if let buildMatch = release.name.firstMatch(of: /\(build (\d+)\)/) {
                            Text(" (build \(buildMatch.1))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    HStack(spacing: 0) {
                        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                        if let currentDate = appState.currentVersionReleaseDate {
                            Text(currentDate.formatted(date: .abbreviated, time: .omitted))
                            Text(" · ")
                        }
                        Text("v\(current) (build \(currentBuild))")
                        Text(" · ")
                        Text(l10n["updates.current"])
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Divider()

            // Release notes
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n["updates.release.notes"])
                        .font(.headline)

                    releaseNotesBody(release.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 240)

            Divider()

            // Footer
            HStack {
                Button(l10n["updates.view.github"]) {
                    if let url = URL(string: release.htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer()

                Button(l10n["updates.later"]) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(l10n["updates.skip.version"]) {
                    appState.skipVersion(release.version)
                    dismiss()
                }

                Button(l10n["updates.download"]) {
                    Task {
                        await appState.downloadUpdate(release)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Downloading

    private func downloadingContent(progress: UpdateProgress, l10n: L10n) -> some View {
        VStack(spacing: 16) {
            Text(l10n["updates.downloading"])
                .font(.headline)
                .padding(.top, 20)

            ProgressView(value: progress.percentage)
                .padding(.horizontal)

            HStack {
                Text(formatBytes(progress.bytesDownloaded))
                Text("/")
                Text(formatBytes(progress.totalBytes))
                Text("—")
                Text(formatSpeed(progress.speedBytesPerSecond))
                if progress.speedBytesPerSecond > 0, progress.etaSeconds < 3600 {
                    Text("—")
                    Text(formatETA(progress.etaSeconds, l10n: l10n))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("\(Int(progress.percentage * 100))%")
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(l10n["common.cancel"]) {
                appState.cancelDownload()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Ready to Install

    private func readyContent(release _: GitHubRelease, l10n: L10n) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .padding(.top, 20)

            Text(l10n["updates.download.complete"])
                .font(.headline)

            Text(l10n["updates.install.restart.message"])
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack {
                Button(l10n["updates.install.later"]) {
                    dismiss()
                }

                Button(l10n["updates.install.restart"]) {
                    Task {
                        await appState.installUpdate()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Installing

    private func installingContent(l10n: L10n) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 20)

            Text(l10n["updates.installing"])
                .font(.headline)

            Text(l10n["updates.installing.message"])
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Error

    private func errorContent(error: UpdateError, l10n: L10n) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
                .padding(.top, 20)

            Text(l10n["common.error"])
                .font(.headline)

            Text(error.errorDescription ?? "Unknown error")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(l10n["common.dismiss"]) {
                appState.updateStatus = .idle
                dismiss()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    private func formatETA(_ seconds: Double, l10n: L10n) -> String {
        let s = Int(seconds)
        if s < 60 {
            return l10n.t("updates.eta.seconds", "\(s)")
        }
        return l10n.t("updates.eta.minutes", "\(s / 60)")
    }

    // MARK: - Markdown Rendering

    /// Renders GitHub release notes as structured views with proper bullet indentation.
    private func releaseNotesBody(_ markdown: String) -> some View {
        let lines = markdown.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 4)
                } else if trimmed.hasPrefix("## ") {
                    Text(String(trimmed.dropFirst(3)))
                        .font(.body.bold())
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("# ") {
                    Text(String(trimmed.dropFirst(2)))
                        .font(.title3.bold())
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .font(.body)
                        Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 4)
                } else {
                    Text(inlineMarkdown(trimmed))
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Parses inline markdown (bold, links, code) into an AttributedString.
    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
