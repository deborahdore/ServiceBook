import SwiftUI
import SwiftData
import QuickLook
import VisionKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

extension DueStatus {
    var color: Color {
        switch self {
        case .overdue: .red
        case .dueSoon: .orange
        case .upcoming: .green
        case .noInterval: .gray
        case .completed: .blue
        }
    }

    var symbol: String {
        switch self {
        case .overdue: "exclamationmark.circle.fill"
        case .dueSoon: "clock.badge.exclamationmark.fill"
        case .upcoming: "checkmark.circle"
        case .noInterval: "minus.circle"
        case .completed: "checkmark.seal.fill"
        }
    }
}

struct StatusPill: View {
    let status: DueStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
    }
}

struct TaskRow: View {
    let task: MaintenanceTask
    let info: DueInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: TaskCategory.symbol(for: task.category))
                .font(.body)
                .foregroundStyle(info.status.color)
                .frame(width: 28, height: 28)
                .background(info.status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LS(task.title)).font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Text(task.action.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(task.intervalText).font(.caption).foregroundStyle(.secondary)
                if info.status == .completed {
                    if let d = info.lastDoneDate {
                        Text("Done on \(Fmt.date(d))").font(.caption).foregroundStyle(.blue)
                    } else {
                        Text("Skipped (before tracking started)").font(.caption).foregroundStyle(.secondary)
                    }
                } else if !info.dueText.isEmpty {
                    Text(L("Due %@", info.dueText))
                        .font(.caption)
                        .foregroundStyle(info.status == .upcoming ? Color.secondary : info.status.color)
                }
                if info.status != .completed && info.status != .noInterval {
                    ProgressView(value: min(max(info.progress, 0), 1))
                        .tint(info.status.color)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Numeric text field bound to a String (keeps editing simple and locale-agnostic).
struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
    }
}

extension String {
    /// Parses "12 000", "12,000", "12.000" as 12000.
    var intValue: Int? {
        let digits = filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    var doubleValue: Double? {
        let cleaned = replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }
}

// MARK: - Attachments

/// A file chosen in a form but not yet saved.
struct PendingAttachment: Identifiable {
    let id = UUID()
    var filename: String
    var typeIdentifier: String
    var data: Data
}

enum AttachmentIO {
    /// Reads a file picked with .fileImporter (security-scoped).
    static func read(_ url: URL) -> PendingAttachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
        return PendingAttachment(filename: url.lastPathComponent, typeIdentifier: type, data: data)
    }

    /// Writes an attachment to a temporary file so it can be previewed / shared.
    static func tempURL(filename: String, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = filename.isEmpty ? "file" : filename.replacingOccurrences(of: "/", with: "-")
            let url = dir.appendingPathComponent(safe)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func pdf(from images: [UIImage]) -> Data? {
        let doc = PDFDocument()
        for (i, image) in images.enumerated() {
            if let page = PDFPage(image: image) { doc.insert(page, at: i) }
        }
        return doc.pageCount > 0 ? doc.dataRepresentation() : nil
    }

    static func symbol(for typeIdentifier: String, filename: String) -> String {
        if typeIdentifier == UTType.pdf.identifier || filename.lowercased().hasSuffix(".pdf") { return "doc.richtext" }
        if let t = UTType(typeIdentifier), t.conforms(to: .image) { return "photo" }
        return "doc"
    }
}

struct AttachmentRow: View {
    let name: String
    let typeIdentifier: String
    let size: Int
    var date: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: AttachmentIO.symbol(for: typeIdentifier, filename: name))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).lineLimit(1)
                Text([ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                      date.map { Fmt.date($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Wraps VisionKit's document camera; returns the scan as a single PDF.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(AttachmentIO.pdf(from: images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }
    }
}

// MARK: - Vehicle photo

/// The vehicle's icon: its photo when one is set, otherwise the symbol for its type.
struct VehicleIcon: View {
    let photo: Data?
    let kind: VehicleKind
    var size: CGFloat = 44

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
        } else {
            Image(systemName: kind.symbol)
                .font(size >= 60 ? .largeTitle : .title2)
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.23))
        }
    }
}

enum VehiclePhoto {
    /// Loads a picked image, crops it to a square and shrinks it so the icon stays light to store.
    static func load(_ item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        let crop = min(image.size.width, image.size.height)
        let side = min(crop, 600)
        let k = side / crop
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - image.size.width * k) / 2, y: (side - image.size.height * k) / 2,
                                  width: image.size.width * k, height: image.size.height * k))
        }
        return square.jpegData(compressionQuality: 0.8)
    }
}

/// Form row to choose, change or remove the photo used as the vehicle's icon.
struct VehiclePhotoField: View {
    @Binding var photo: Data?
    let kind: VehicleKind
    @State private var item: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 14) {
            VehicleIcon(photo: photo, kind: kind, size: 60)
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $item, matching: .images) {
                    if photo == nil { Text("Choose photo") } else { Text("Change photo") }
                }
                if photo != nil {
                    Button("Remove photo", role: .destructive) { photo = nil }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = await VehiclePhoto.load(newItem) { photo = data }
                item = nil
            }
        }
    }
}

struct EmptyHint: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}
