import SwiftUI
import AppKit
import QuickLookUI
import ShiroCore

struct FileCard: View {
    @EnvironmentObject var store: AppStore
    let file: ChatFile
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.name.lowercased().hasSuffix("pdf") ? "doc.richtext" : "doc.fill").font(.system(size: 26)).foregroundStyle(Palette.mint).frame(width: 44, height: 48).background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) { Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(2); Text(file.bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file) : "On your computer").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            Spacer()
            Button { store.previewFile(file) } label: { Image(systemName: "eye").frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(Palette.muted).help("Preview " + file.name).accessibilityLabel("Preview " + file.name)
            Button { store.exportArtifact(file.path) } label: { Image(systemName: "arrow.down.to.line").frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(Palette.muted).help("Download " + file.name).accessibilityLabel("Download " + file.name)
        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line)).frame(maxWidth: 470).disabled(store.fileBusy || !store.vmReady)
    }
}

struct FilesView: View {
    @EnvironmentObject var store: AppStore
    var compact = false
    @State private var folder = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact { PageHeading(eyebrow: "Your shared computer", title: "Files", subtitle: "Every bot can create work here. Preview a result or save it to your Mac.") }
            HStack { Button("Home") { folder = ""; reload() }; if !folder.isEmpty { Button("Back") { folder = (folder as NSString).deletingLastPathComponent; reload() } }; Spacer(); Button("Refresh") { reload() } }.disabled(!store.vmReady)
            if !folder.isEmpty { Text(folder).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(2) }
            ScrollView { LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.artifacts, id: \.text) { item in
                    let path = item["path"].string ?? ""
                    if item["directory"].bool == true {
                        Button { folder = path; reload() } label: { Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder.fill").font(.system(size: 14)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    } else { FileCard(file: ChatFile(path: path, bytes: Int(item["bytes"].number ?? 0))) }
                }
                if store.artifacts.isEmpty { Text(store.vmReady ? "No files in this folder yet." : "Connect your computer to browse files.").foregroundStyle(Palette.muted).padding(.top, 30) }
            } }
        }.padding(compact ? 14 : 30).task(id: store.vmReady) { reload() }
    }
    private func reload() { Task { await store.refreshArtifacts(path: folder) } }
}

struct FilePreviewView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(store.previewURL?.lastPathComponent ?? "Preview").font(.system(size: 15, weight: .medium)); Spacer(); Button("Save to Mac…") { if let url = store.previewURL { let panel = NSSavePanel(); panel.nameFieldStringValue = url.lastPathComponent; if panel.runModal() == .OK, let destination = panel.url { do { try Data(contentsOf: url).write(to: destination, options: .atomic) } catch { store.error = error.localizedDescription } } } }; Button("Done") { store.previewURL = nil } }.padding(18)
            Divider()
            if let url = store.previewURL { QuickPreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.frame(width: 820, height: 620)
    }
}

struct QuickPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = true; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}
