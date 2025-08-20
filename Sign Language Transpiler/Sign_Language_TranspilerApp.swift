//
//  Sign_Language_TranspilerApp.swift
//  Sign Language Transpiler
//
//  Created by Nikola Andreev on 20.08.25.
//
import SwiftUI

@main
struct Sign_Language_TranspilerApp: App {
    @StateObject private var storage = StorageService()
    @StateObject private var catalog = GestureCatalog()
    @StateObject private var wc = WCSessionService.shared

    init() {
        // Activate WatchConnectivity early
        WCSessionService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(storage: storage)
                .environmentObject(catalog)
                .environmentObject(wc)
                .onAppear {
                    catalog.loadFromBundle()  // load Gestures.json
                }
        }
    }
}
