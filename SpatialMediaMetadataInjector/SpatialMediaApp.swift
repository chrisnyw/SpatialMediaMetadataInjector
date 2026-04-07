//
//  SpatialMediaApp.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import SwiftUI

@main
struct SpatialMediaApp: App {
    var body: some Scene {
        WindowGroup {
            InjectorView()
        }
        .defaultSize(width: 720, height: 420)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}
