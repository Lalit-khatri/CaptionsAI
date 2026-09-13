import Foundation

// MARK: - VideoLibrary

/// Durable storage for imported videos.
///
/// Two separate things used to be wrong about where a project's video lived,
/// and either one alone is enough to lose it:
///
/// 1. **It was written to `tmp/`.** The system reclaims that directory
///    whenever it feels short of space, with no warning and no notification.
/// 2. **Its absolute path was persisted.** The container directory's UUID
///    changes when the app is reinstalled, so a path recorded today does not
///    exist tomorrow even if the file was never touched.
///
/// The failure is quiet, which is what makes it expensive: `thumbnailData`
/// lives in the database, so the project keeps rendering its thumbnail in the
/// list long after the video it points at has gone. The user sees an intact
/// project until they open it.
///
/// So videos live here, under Application Support, and a project stores only
/// the **file name**. The directory is re-derived at every read, which makes a
/// container move a non-event.
enum VideoLibrary {
    /// Where imported videos are kept.
    ///
    /// Application Support rather than Documents: these are the app's working
    /// copies, not documents the user manages, and Documents is visible in the
    /// Files app when file sharing is on.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Videos", isDirectory: true)
    }

    /// Creates the directory if it is not there yet.
    @discardableResult
    static func ensureDirectory() throws -> URL {
        let url = directory
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Writing

    /// Writes `data` into the library and returns the reference to persist.
    static func store(data: Data, fileExtension: String = "mp4") throws -> String {
        try ensureDirectory()
        let name = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Moves a file already on disk into the library and returns the reference
    /// to persist. Falls back to a copy when the source is on another volume.
    static func store(movingFileAt source: URL) throws -> String {
        try ensureDirectory()
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return name
    }

    // MARK: - Reading

    /// The reference to persist for `url`.
    ///
    /// A file inside the library is recorded by name alone, so it survives the
    /// container moving. Anything else keeps its full URL, because we do not
    /// own it and cannot promise it will be there.
    static func reference(for url: URL) -> String {
        let inLibrary = url.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
        return inLibrary ? url.lastPathComponent : url.absoluteString
    }

    /// Resolves a stored reference to a file that exists, or `nil`.
    ///
    /// Returning `nil` for a missing file is deliberate. The previous
    /// behaviour handed back a perfectly well-formed URL pointing at nothing,
    /// so every caller's `guard let url` succeeded and the failure surfaced as
    /// a black frame several screens later.
    static func resolve(_ reference: String) -> URL? {
        guard !reference.isEmpty else { return nil }

        // The current form: a bare name, resolved against today's container.
        if !reference.contains("/") {
            return existing(directory.appendingPathComponent(reference))
        }

        // A full URL, either from before this change or from somewhere outside
        // the library. Honour it if it is still valid.
        let stored = URL(string: reference) ?? URL(fileURLWithPath: reference)
        if let found = existing(stored) { return found }

        // It is not, which for a container path is the expected state after a
        // reinstall. The file name is the only durable part of the old path,
        // so look for it where videos live now.
        return existing(directory.appendingPathComponent(stored.lastPathComponent))
    }

    /// Deletes the file a reference points at, if we own it. Missing files are
    /// not an error: the caller is trying to reach a state, not perform a step.
    static func remove(_ reference: String) {
        guard let url = resolve(reference) else { return }
        guard url.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
