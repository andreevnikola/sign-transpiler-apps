//
//  Signer.swift
//  Sign Language Transpiler
//
//  Created by Nikola Andreev on 20.08.25.
//


import Foundation

struct Signer: Identifiable, Hashable {
    let id: String     // folder-safe id (e.g., UUID or slug)
    let name: String
    let folderURL: URL
}

struct GestureGroup: Identifiable, Hashable {
    let id: String     // gestureId (e.g., "IDVAM", "NE")
    let csvFiles: [URL]
    var count: Int { csvFiles.count }
}
