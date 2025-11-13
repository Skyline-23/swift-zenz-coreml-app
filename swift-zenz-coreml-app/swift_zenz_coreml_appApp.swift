//
//  swift_zenz_coreml_appApp.swift
//  swift-zenz-coreml-app
//
//  Created by Buseong Kim on 11/12/25.
//


import SwiftUI
import SwiftData

@main
struct swift_zenz_coreml_appApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: BenchmarkCase.self)
    }
}
