// DahlStar_User_Interface_AppApp.swift — macOS app entry point.

import SwiftUI

@main
struct DahlStar_User_Interface_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { DahlStarCommands() }
        .defaultSize(width: 540, height: 740)
        .windowResizability(.contentMinSize)
    }
}
