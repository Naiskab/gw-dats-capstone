import SwiftUI

struct SplashScreenView: View {
    @State private var showLogo    = false
    @State private var showName    = false
    @State private var spinDegrees = 0.0

    var body: some View {
        GeometryReader { proxy in
            let logoSize  = BrandLogoView.logoSize(for: proxy.size)
            let titleSize = min(max(logoSize * 0.35, 34), 54)
            let spacing   = max(18, logoSize * 0.16)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: spacing) {
                    BrandLogoView(containerSize: proxy.size)
                        .opacity(showLogo ? 1 : 0)
                        .scaleEffect(showLogo ? 1 : 0.92)
                        .rotation3DEffect(
                            .degrees(spinDegrees),
                            axis: (x: 0, y: 1, z: 0)
                        )

                    Text("RideShift")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .opacity(showName ? 1 : 0)
                        .offset(y: showName ? 0 : 10)
                }
                .padding(.horizontal, 24)
            }
        }
        .task {
            // 1. Fade in logo
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.3)) {
                showLogo = true
            }

            // 2. Wait for fade-in to finish, then spin 2 full rotations smoothly
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.linear(duration: 0.3)) {
                spinDegrees = 360   // 2 × 360°
            }

            // 3. Wait for spin to finish, then show name
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.35)) {
                showName = true
            }
        }
    }
}
