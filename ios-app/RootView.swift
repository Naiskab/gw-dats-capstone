import SwiftUI

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            MainView(startIntro: !showSplash)

            if showSplash {
                SplashScreenView()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            showSplash = false
        }
    }
}
