import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Files app integration: the Mac's open/save panels and clipboard, done the iOS way.
enum Files {
    /// Writes data to a temporary file with this name and returns its URL (for sharing / saving to Files).
    static func temp(_ name: String, _ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BillBoxShare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// The share sheet ("Save to Files", AirDrop, Mail, WhatsApp …) for a file.
    @MainActor
    static func share(_ url: URL) {
        guard let top = topController() else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    /// Saves data under a file name: opens the share sheet, where "Save to Files" picks the folder.
    @MainActor
    @discardableResult
    static func save(_ name: String, data: Data) -> URL? {
        guard let url = temp(name, data) else { return nil }
        share(url)
        return url
    }

    static func copy(_ text: String) { UIPasteboard.general.string = text }

    /// A JSON file picked in Files, as text (nil when cancelled or unreadable).
    @MainActor
    static func pickJSON() async -> String? {
        guard let url = await pick([.json]) else { return nil }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var text: String?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in text = try? String(contentsOf: u, encoding: .utf8) }
        return text
    }

    @MainActor
    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }

    /// The Files picker (UIDocumentPickerViewController). SwiftUI's fileImporter does not appear when another sheet or
    /// dialog modifier sits on the same screen, so BillBox presents the picker itself. nil when cancelled.
    @MainActor
    static func pick(_ types: [UTType]) async -> URL? {
        guard let top = topController() else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
            picker.allowsMultipleSelection = false
            let d = PickerDelegate { url in c.resume(returning: url) }
            picker.delegate = d
            PickerDelegate.current = d          // kept alive until the picker closes
            top.present(picker, animated: true)
        }
    }

    /// Copies what was picked (a file or a whole folder, from this iPhone, iCloud Drive or another provider) into a private
    /// folder and returns that folder. iCloud items are downloaded first; a .zip is unpacked.
    static func importPicked(_ url: URL) throws -> String {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("BillBoxImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        var failure: Error?
        var coordError: NSError?
        // a coordinated read makes iCloud Drive download the item (and everything inside a folder) before it is copied
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readable in
            do { try fm.copyItem(at: readable, to: dest) } catch { failure = error }
        }
        if let e = coordError ?? failure as NSError? {
            // some providers only hand over a folder as one packed copy
            var packedError: NSError?
            var unpacked = false
            NSFileCoordinator().coordinate(readingItemAt: url, options: .forUploading, error: &packedError) { zip in
                if let d = try? Data(contentsOf: zip), (try? Unzip.extract(d, to: dir.path)) != nil { unpacked = true }
            }
            if !unpacked { throw e }
        }
        if dest.pathExtension.lowercased() == "zip", let d = try? Data(contentsOf: dest) {
            try Unzip.extract(d, to: dir.appendingPathComponent("unzipped").path)
            try? fm.removeItem(at: dest)
        }
        return dir.path
    }
}

/// Hands the picked URL back once (picked or cancelled).
final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    static var current: PickerDelegate?
    private var done: ((URL?) -> Void)?
    init(_ done: @escaping (URL?) -> Void) { self.done = done }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    private func finish(_ url: URL?) {
        done?(url)
        done = nil
        PickerDelegate.current = nil
    }
}

/// Folders picked in the Files app stay usable across launches through bookmarks (the backup folder, decision D4).
enum FolderAccess {
    private static let key = "folderBookmarks"

    static func remember(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:]
        all[url.path] = data
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Starts access to a remembered folder that contains `path`; the returned closure ends it. nil when no bookmark applies.
    static func open(_ path: String) -> (() -> Void)? {
        let all = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:]
        guard let hit = all.filter({ path == $0.key || path.hasPrefix($0.key + "/") }).max(by: { $0.key.count < $1.key.count }) else { return nil }
        let root = hit.key, data = hit.value
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var m = all
            m[root] = fresh
            UserDefaults.standard.set(m, forKey: key)
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return { url.stopAccessingSecurityScopedResource() }
    }
}

/// Tab-separated text for pasting into Excel / Numbers.
func tsv(_ header: [String], _ rows: [[String]]) -> String {
    ([header] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
}
