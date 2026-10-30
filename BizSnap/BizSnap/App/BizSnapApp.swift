import SwiftUI

@main
struct BizSnapApp: App {
    @StateObject private var client = AgentClient()

    var body: some Scene {
        WindowGroup {
            ThreadListView()
                .environmentObject(client)
                .tint(Theme.accent)
        }
    }
}
