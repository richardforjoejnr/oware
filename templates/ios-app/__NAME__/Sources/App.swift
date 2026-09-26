import SwiftUI

@main
struct __NAME__App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
            Text("__DISPLAY__")
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("home-title")
        }
        .padding()
    }
}
