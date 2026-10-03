import SwiftUI

@main
struct LeluLudoApp: App {
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
            Text("Lelu Ludo")
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("home-title")
        }
        .padding()
    }
}
