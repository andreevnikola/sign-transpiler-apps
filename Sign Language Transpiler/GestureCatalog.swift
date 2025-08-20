import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Models

struct GestureSpec: Identifiable, Codable, Hashable {
    let id: String      // e.g., "DA"
    let name_bg: String // e.g., "Да"
    let tech: Int       // e.g., 1
}

// Per-tech info now includes BOTH a human name and an SF Symbol icon
struct TechInfo: Codable, Hashable {
    let name: String    // e.g., "Dominant Hand Apple Watch"
    let icon: String    // e.g., "applewatch.case" (SF Symbol)
}

struct GestureCatalogFile: Codable {
    // Now: "1": { "name": "...", "icon": "..." }
    let techLegend: [String: TechInfo]
    let gestures: [GestureSpec]
}

final class GestureCatalog: ObservableObject {
    @Published var gestures: [GestureSpec] = []
    @Published var techLegend: [Int: TechInfo] = [:]
    @Published var status: String = "Not loaded"

    // MARK: - Load

    func loadFromBundle() {
        status = "Loading…"

        // 1) Exact name
        if let url = Bundle.main.url(forResource: "Gestures", withExtension: "json") {
            decode(from: url, hint: "Bundle.main url(forResource:)"); return
        }

        // 2) Case-insensitive match
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil),
           let match = urls.first(where: { $0.lastPathComponent.lowercased() == "gestures.json" }) {
            decode(from: match, hint: "Bundle scan (case-insensitive)"); return
        }

        // 3) Recursive scan
        if let resURL = Bundle.main.resourceURL {
            let fm = FileManager.default
            if let en = fm.enumerator(at: resURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in en where
                        fileURL.pathExtension.lowercased() == "json" &&
                        fileURL.lastPathComponent.lowercased() == "gestures.json" {
                    decode(from: fileURL, hint: "ResourceURL enumerator"); return
                }
            }
        }

        // 4) Documents
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = docs.appendingPathComponent("Gestures.json")
            if FileManager.default.fileExists(atPath: file.path) {
                decode(from: file, hint: "Documents/Gestures.json"); return
            }
        }

        // 5) Data Asset (optional)
        #if canImport(UIKit)
        if let asset = NSDataAsset(name: "Gestures") {
            let url = writeTemp(asset.data, fileName: "Gestures_from_DataAsset.json")
            decode(from: url, hint: "NSDataAsset(\"Gestures\")"); return
        }
        #endif

        loadEmbeddedFallback(reason: "Gestures.json not found")
    }

    private func decode(from url: URL, hint: String) {
        do {
            let data = try Data(contentsOf: url)
            try decodeData(data, hint: hint + " → " + url.lastPathComponent)
        } catch {
            let err = "❌ Read error via \(hint): \(error)"
            NSLog("%@", err); status = err
            loadEmbeddedFallback(reason: err)
        }
    }

    private func decodeData(_ data: Data, hint: String) throws {
        do {
            let file = try JSONDecoder().decode(GestureCatalogFile.self, from: data)
            self.gestures = file.gestures
            var map: [Int: TechInfo] = [:]
            for (k, v) in file.techLegend { if let ik = Int(k) { map[ik] = v } }
            self.techLegend = map
            let ok = "✅ Loaded \(gestures.count) gestures via \(hint)"
            NSLog("%@", ok); status = ok
        } catch {
            let err = "❌ Decode error via \(hint): \(error)"
            NSLog("%@", err); status = err
            loadEmbeddedFallback(reason: err)
        }
    }

    private func writeTemp(_ data: Data, fileName: String) -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    private func loadEmbeddedFallback(reason: String) {
        // Embedded fallback now includes icon strings
        let fallback = """
        {
          "techLegend": {
            "1": { "name": "Dominant Hand Apple Watch", "icon": "applewatch.case" }
          },
          "gestures": [
            { "id": "DA",      "name_bg": "Да",      "tech": 1 },
            { "id": "NE",      "name_bg": "Не",      "tech": 1 },
            { "id": "SPRI",    "name_bg": "Спри",    "tech": 1 },
            { "id": "IDVAM",   "name_bg": "Идвам",   "tech": 1 },
            { "id": "OTIVAM",  "name_bg": "Отивам",  "tech": 1 },
            { "id": "GOLYAM",  "name_bg": "Голям",   "tech": 1 },
            { "id": "MALAK",   "name_bg": "Малък",   "tech": 1 },
            { "id": "DAI",     "name_bg": "Дай",     "tech": 1 },
            { "id": "POKAZHI", "name_bg": "Покажи",  "tech": 1 },
            { "id": "HODI",    "name_bg": "Ходи",    "tech": 1 },
            { "id": "BARZO",   "name_bg": "Бързо",   "tech": 1 },
            { "id": "BAVNO",   "name_bg": "Бавно",   "tech": 1 },
            { "id": "PROBLEM", "name_bg": "Проблем", "tech": 1 },
            { "id": "DOMA",    "name_bg": "Дома",    "tech": 1 },
            { "id": "RABOTA",  "name_bg": "Работа",  "tech": 1 }
          ]
        }
        """
        guard let data = fallback.data(using: .utf8) else {
            let msg = "❌ Embedded fallback corrupted."
            NSLog("%@", msg); status = msg; return
        }
        try? decodeData(data, hint: "Embedded fallback (\(reason))")
    }

    // MARK: - API for views

    func legendText(for tech: Int) -> String {
        techLegend[tech]?.name ?? "Unknown"
    }

    func iconName(for tech: Int) -> String {
        techLegend[tech]?.icon ?? "questionmark.circle"
    }
}
