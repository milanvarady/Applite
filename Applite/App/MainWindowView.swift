import SwiftUI

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    let applicationDelegate: ApplicationDelegate

    var body: some View {
        ContentView()
            .onAppear {
                applicationDelegate.reopenMainWindow = {
                    openWindow(id: "main")
                }
            }
    }
}
