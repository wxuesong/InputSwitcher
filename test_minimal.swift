import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        MenuBarExtra {
            Button("测试") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "keyboard")
        }
    }
}
