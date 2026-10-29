import SwiftUI

/// Choose, download or delete the open model that reads manuals on the iPhone (MLX).
struct LocalModelView: View {
    @AppStorage(LocalModel.selectedKey) private var selected: LocalModel = .small
    @State private var downloading: LocalModel?
    @State private var progress = 0.0
    @State private var error: String?
    @State private var version = 0   // redraws after a download or delete

    var body: some View {
        let _ = version
        Form {
            Section {
                Text("Reads your manual on this iPhone with a free open model (Qwen3), run by Apple's MLX. No Apple Intelligence needed: it works offline and in every country. Download it once, preferably on Wi-Fi.")
                    .font(.callout)
            }
            Section {
                ForEach(LocalModel.allCases) { row($0) }
            } header: {
                Text("Model")
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Stored on this iPhone only, outside iCloud backups.")
                }
            }
        }
        .navigationTitle("On-device model")
    }

    private func row(_ model: LocalModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected == model ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected == model ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).font(.headline)
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
                if downloading == model {
                    ProgressView(value: progress)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else if model.isDownloaded {
                    HStack {
                        Label("Downloaded · \(model.size)", systemImage: "checkmark").foregroundStyle(.green)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            model.delete()
                            version += 1
                        }
                    }
                    .font(.caption)
                } else {
                    Button("Download \(model.size)") { download(model) }
                        .font(.caption)
                        .disabled(downloading != nil)
                }
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = model }
    }

    private func download(_ model: LocalModel) {
        downloading = model
        progress = 0
        error = nil
        Task {
            do {
                try await model.download { progress = $0 }
                selected = model
            } catch {
                self.error = error.localizedDescription
            }
            downloading = nil
            version += 1
        }
    }
}
