import Foundation

/// File layout (inside app's Documents):
/// Documents/raw_csv/
///   <signerId>__<name>/
///     u<userId>_g<GESTURE>_r<rep>_s<SESSION>_<yyyyMMdd-HHmmss>.csv
///
/// All grouping/filtering is done via filename parsing (no file I/O).
final class StorageService: ObservableObject {
    private let fm = FileManager.default
    private let baseDirName = "raw_csv"
    private lazy var docsURL: URL = {
        fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    }()
    private lazy var baseURL: URL = {
        let url = docsURL.appendingPathComponent(baseDirName, isDirectory: true)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    // MARK: - Models

    struct Meta: Hashable {
        let user: String
        let gesture: String
        let rep: String
        let session: String
        let timestamp: String
    }

    // MARK: - Signers

    func listSigners() -> [Signer] {
        guard let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return contents.compactMap { url in
            guard url.hasDirectoryPath else { return nil }
            let folderName = url.lastPathComponent
            let parts = folderName.split(separator: "__", maxSplits: 1, omittingEmptySubsequences: false)
            let id = parts.first.map(String.init) ?? folderName
            let name = parts.count > 1 ? String(parts[1]) : id
            return Signer(id: id, name: name, folderURL: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func createSigner(name: String) throws -> Signer {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString.lowercased()
        let safeName = trimmed.replacingOccurrences(of: "/", with: "-")
        let folder = baseURL.appendingPathComponent("\(id)__\(safeName)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return Signer(id: id, name: safeName, folderURL: folder)
    }

    func deleteSigner(_ signer: Signer) throws {
        try fm.removeItem(at: signer.folderURL)
    }

    // MARK: - Sessions

    /// Distinct sessions for a signer (parsed from filenames)
    func listSessions(for signer: Signer) -> [String] {
        let files = signerCSVFiles(signer)
        var set = Set<String>()
        for url in files {
            if let meta = parseMeta(url.lastPathComponent) {
                set.insert(meta.session)
            }
        }
        return Array(set).sorted()
    }

    /// Delete all CSVs that belong to a given session (for this signer).
    func deleteSession(_ signer: Signer, session: String) throws {
        let files = signerCSVFiles(signer)
        for url in files {
            if let meta = parseMeta(url.lastPathComponent), meta.session == session {
                try fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Gestures

    /// Group CSVs by gesture; if `session` is provided, filter to that session only.
    func listGestureGroups(for signer: Signer, session: String? = nil) -> [GestureGroup] {
        let files = signerCSVFiles(signer)
        var byGesture: [String: [URL]] = [:]
        for url in files {
            guard let meta = parseMeta(url.lastPathComponent) else { continue }
            if let s = session, meta.session != s { continue }
            byGesture[meta.gesture, default: []].append(url)
        }
        return byGesture
            .map { GestureGroup(id: $0.key, csvFiles: $0.value.sorted { $0.lastPathComponent < $1.lastPathComponent }) }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// Delete all CSVs of a gesture across all sessions.
    func deleteGestureAllSessions(_ signer: Signer, gestureId: String) throws {
        let files = signerCSVFiles(signer)
        for url in files {
            if let meta = parseMeta(url.lastPathComponent), meta.gesture == gestureId {
                try fm.removeItem(at: url)
            }
        }
    }

    /// Delete all CSVs of a gesture within a specific session.
    func deleteGestureInSession(_ signer: Signer, gestureId: String, session: String) throws {
        let files = signerCSVFiles(signer)
        for url in files {
            if let meta = parseMeta(url.lastPathComponent),
               meta.gesture == gestureId, meta.session == session {
                try fm.removeItem(at: url)
            }
        }
    }

    // Save a CSV into a signer folder
    func saveCSV(data: Data, fileName: String, to signer: Signer) throws -> URL {
        let url = signer.folderURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Internals

    private func signerCSVFiles(_ signer: Signer) -> [URL] {
        guard let files = try? fm.contentsOfDirectory(at: signer.folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return files.filter { $0.pathExtension.lowercased() == "csv" }
    }

    /// Robust parser for filename:
    /// u{user}_g{gesture}_r{rep}_s{session}_{yyyyMMdd-HHmmss}.csv
    /// Avoids mis-deletion by always matching token prefixes.
    private func parseMeta(_ filename: String) -> Meta? {
        let base = filename.hasSuffix(".csv") ? String(filename.dropLast(4)) : filename
        let parts = base.split(separator: "_")
        // Expected tokens: ["u{user}", "g{gesture}", "r{rep}", "s{session}", "{timestamp}"]
        guard parts.count >= 5 else { return nil }

        func stripPrefix(_ token: Substring, _ prefix: Character) -> String? {
            guard token.first == prefix else { return nil }
            return String(token.dropFirst())
        }

        guard let user = stripPrefix(parts[0], "u"),
              let gesture = stripPrefix(parts[1], "g"),
              let rep = stripPrefix(parts[2], "r"),
              let session = stripPrefix(parts[3], "s")
        else { return nil }

        let timestamp = String(parts[4]) // we don't need to validate format here
        guard !user.isEmpty, !gesture.isEmpty, !rep.isEmpty, !session.isEmpty, !timestamp.isEmpty else { return nil }

        return Meta(user: user, gesture: gesture, rep: rep, session: session, timestamp: timestamp)
    }

    // Demo seed to visualize sessions & gestures
    func seedDemoDataIfEmpty() {
        let signers = listSigners()
        guard signers.isEmpty else { return }
        let names = ["Alex", "Mira"]
        for n in names {
            if let s = try? createSigner(name: n) {
                let samples = [
                    "u\(s.id.prefix(4))_gIDVAM_r01_sA_20250101-120000.csv",
                    "u\(s.id.prefix(4))_gNE_r02_sA_20250101-120100.csv",
                    "u\(s.id.prefix(4))_gNE_r03_sB_20250101-120130.csv",
                    "u\(s.id.prefix(4))_gDA_r01_sB_20250101-120200.csv"
                ]
                for f in samples {
                    let url = s.folderURL.appendingPathComponent(f)
                    let csv = "ts,ax,ay\n0.0,0.01,0.02\n0.02,0.03,0.04\n"
                    try? csv.data(using: .utf8)?.write(to: url)
                }
            }
        }
    }
}
