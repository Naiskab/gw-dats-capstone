import SwiftUI
import MapKit
import CoreLocation

struct MainView: View {
    let startIntro: Bool
    let animateFromSplash: Bool

    private let features: [LandingFeature] = [
        .init(
            icon: "mappin.and.ellipse",
            title: "Find Cheaper Pickups",
            subtitle: "We search nearby streets for lower fares",
            accentColor: Color(red: 0.4, green: 0.8, blue: 1.0)
        ),
        .init(
            icon: "chart.bar.xaxis.ascending",
            title: "Compare Before You Confirm",
            subtitle: "See all options ranked by price and walk time",
            accentColor: Color(red: 0.6, green: 0.9, blue: 0.6)
        ),
        .init(
            icon: "figure.walk",
            title: "Small Walk. Bigger Savings.",
            subtitle: "A short walk can save you money every ride",
            accentColor: Color(red: 1.0, green: 0.8, blue: 0.4)
        )
    ]

    @State private var overlayMovedToTop = false
    @State private var showHeader = false
    @State private var showOtherContent = false
    @State private var showOverlayHeader = false
    @State private var didRunIntro = false
    @State private var targetHeaderMidY: CGFloat?
    @State private var showNextLanding = false
    @State private var visibleCardCount = 0

    init(startIntro: Bool = true, animateFromSplash: Bool = true) {
        self.startIntro = startIntro
        self.animateFromSplash = animateFromSplash
        _showHeader = State(initialValue: !animateFromSplash)
        _showOtherContent = State(initialValue: !animateFromSplash)
        _showOverlayHeader = State(initialValue: animateFromSplash)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let width = proxy.size.width
                let horizontalPadding = max(20, width * 0.06)
                let logoSize = BrandLogoView.logoSize(for: proxy.size)
                let appNameSize = min(max(logoSize * 0.35, 34), 54)
                let subtitleSize = min(max(width * 0.055, 19), 30)
                let headerSpacing = max(12, logoSize * 0.08)
                let centerY = proxy.size.height / 2
                let overlayOffsetY = overlayMovedToTop ? ((targetHeaderMidY ?? centerY) - centerY) : 0

                ZStack {
                    LinearGradient(
                        colors: [
                            Color.black,
                            Color(red: 0.02, green: 0.03, blue: 0.08),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 10,
                        endRadius: 460
                    )
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            VStack(spacing: headerSpacing) {
                                headerLockup(
                                    containerSize: proxy.size,
                                    appNameSize: appNameSize,
                                    headerSpacing: headerSpacing,
                                    visible: showHeader,
                                    reportPosition: true
                                )
                                Text("Save money on every ride")
                                    .font(.system(size: subtitleSize, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .multilineTextAlignment(.center)
                                    .opacity(showOtherContent ? 1 : 0)
                                    .offset(y: showOtherContent ? 0 : 8)
                                    .animation(.easeOut(duration: 0.35), value: showOtherContent)
                            }
                            .padding(.top, 18)
                            .padding(.bottom, 10)

                            VStack(spacing: 22) {
                                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                                    FeatureCard(feature: feature)
                                        .opacity(visibleCardCount > index ? 1 : 0)
                                        .offset(y: visibleCardCount > index ? 0 : 22)
                                        .animation(
                                            .spring(response: 0.45, dampingFraction: 0.75)
                                            .delay(Double(index) * 0.12),
                                            value: visibleCardCount
                                        )
                                }
                            }

                            Button(action: { showNextLanding = true }) {
                                HStack(spacing: 8) {
                                    Text("Get Started")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .tracking(0.3)
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.12))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.black.opacity(0.7))
                                    }
                                }
                                .foregroundStyle(Color.black.opacity(0.82))
                                .padding(.vertical, 16)
                                .padding(.leading, 28)
                                .padding(.trailing, 18)
                                .background(
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: .white.opacity(0.18), radius: 20, y: 0)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                            .opacity(showOtherContent ? 1 : 0)
                            .offset(y: showOtherContent ? 0 : 20)
                            .animation(.easeOut(duration: 0.35), value: showOtherContent)

                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 18)
                        .padding(.bottom, max(32, proxy.size.height * 0.06))
                    }

                    if showOverlayHeader {
                        headerLockup(
                            containerSize: proxy.size,
                            appNameSize: appNameSize,
                            headerSpacing: headerSpacing,
                            visible: true,
                            reportPosition: false
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: overlayOffsetY)
                        .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "landing")
                .onPreferenceChange(HeaderCenterPreferenceKey.self) { targetHeaderMidY = $0 }
                .task(id: startIntro) {
                    await runLandingIntroAnimation()
                }
            }
            .navigationDestination(isPresented: $showNextLanding) {
                LoginView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @MainActor
    private func runLandingIntroAnimation() async {
        guard animateFromSplash, startIntro, !didRunIntro else { return }
        didRunIntro = true

        var attempts = 0
        while targetHeaderMidY == nil && attempts < 60 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(10))
        }

        withAnimation(.easeInOut(duration: 0.65)) {
            overlayMovedToTop = true
        }

        try? await Task.sleep(for: .milliseconds(650))
        // 1. Show the real header first — let it fully appear while overlay still covers it
        withAnimation(.easeOut(duration: 0.01)) {
            showHeader = true
        }

        // 2. Small wait so real header is rendered before overlay disappears
        try? await Task.sleep(for: .milliseconds(50))

        // 3. Now fade out the overlay — real header is already underneath, no blink
        withAnimation(.easeOut(duration: 0.2)) {
            showOverlayHeader = false
        }

        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.35)) {
            showOtherContent = true
        }
        // Stagger each card in one by one
        for i in 1...features.count {
            try? await Task.sleep(for: .milliseconds(30))
            visibleCardCount = i
        }
    }

    private func headerLockup(
        containerSize: CGSize,
        appNameSize: CGFloat,
        headerSpacing: CGFloat,
        visible: Bool,
        reportPosition: Bool
    ) -> some View {
        VStack(spacing: headerSpacing) {
            BrandLogoView(containerSize: containerSize)

            Text("RideShift")
                .font(.system(size: appNameSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
        }
        .opacity(visible ? 1 : 0)
        .background {
            if reportPosition {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: HeaderCenterPreferenceKey.self,
                        value: geometry.frame(in: .named("landing")).midY
                    )
                }
            }
        }
    }
}

private struct HeaderCenterPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private struct LandingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}

private struct FeatureCard: View {
    let feature: LandingFeature

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Accent icon — no box, just the icon with a soft glow color
            Image(systemName: feature.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(feature.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(feature.subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [feature.accentColor.opacity(0.35), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// ─────────────────────────────────────────────────────────────────
// REPLACE the existing `private struct RideSearchSetupView` in
// MainView.swift with this entire block.
// ─────────────────────────────────────────────────────────────────

struct RideSearchSetupView: View {
    @State private var pickupText         = ""
    @State private var destinationText    = ""
    @State private var pickupAddress      = ""
    @State private var destinationAddress = ""

    @State private var isSearching        = false
    @State private var isLocating         = false
    @State private var searchResult: SearchResponse?
    @State private var errorMessage: String?

    @StateObject private var api          = RideShiftAPIService()
    @StateObject private var locManager   = LocationManager()

    private var canSearch: Bool {
        !pickupAddress.isEmpty && !destinationAddress.isEmpty && !isSearching
    }

    @State private var glowPulse = false

    var body: some View {
        ZStack {
            // Dark base
            Color.black.ignoresSafeArea()

            // Animated glow orbs
            GeometryReader { geo in
                ZStack {
                    // Blue orb — top left
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.55),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                        .frame(width: 380, height: 380)
                        .offset(
                            x: geo.size.width * 0.05 + (glowPulse ? 12 : -12),
                            y: geo.size.height * 0.08 + (glowPulse ? 8 : -8)
                        )
                        .blur(radius: 30)

                    // Purple orb — center right
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.2, blue: 0.9).opacity(0.45),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                        .frame(width: 380, height: 380)
                        .offset(
                            x: geo.size.width * 0.45 + (glowPulse ? -10 : 10),
                            y: geo.size.height * 0.42 + (glowPulse ? 15 : -15)
                        )
                        .blur(radius: 35)
                }
                .animation(
                    .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                    value: glowPulse
                )
            }
            .ignoresSafeArea()
            .onAppear { glowPulse = true }

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── Header ────────────────────────────────────────
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Where to?")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Find cheaper pickups nearby")
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                            // User avatar
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.top, 12)

                        // ── Pickup ────────────────────────────────────────
                        DarkLocationField(
                            icon: "location.north.line.fill",
                            iconColor: Color(red: 0.4, green: 0.8, blue: 1.0),
                            label: "Pickup",
                            text: $pickupText,
                            onSelect: { completion in
                                pickupAddress = completion.title + (completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")
                            },
                            trailing: {
                                Button {
                                    Task { await fetchCurrentLocation() }
                                } label: {
                                    if isLocating {
                                        ProgressView()
                                            .tint(Color(red: 0.4, green: 0.8, blue: 1.0))
                                            .scaleEffect(0.8)
                                            .frame(width: 60, height: 28)
                                    } else {
                                        Text("Current")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 1.0))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                Capsule()
                                                    .fill(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.12))
                                            )
                                    }
                                }
                            }
                        )
                        .onChange(of: pickupText) { v in
                            if v != pickupAddress { pickupAddress = "" }
                        }

                        // ── Destination ───────────────────────────────────
                        DarkLocationField(
                            icon: "mappin.circle.fill",
                            iconColor: Color(red: 1.0, green: 0.45, blue: 0.45),
                            label: "Destination",
                            text: $destinationText,
                            onSelect: { completion in
                                destinationAddress = completion.title + (completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")
                            }
                        )
                        .onChange(of: destinationText) { v in
                            if v != destinationAddress { destinationAddress = "" }
                        }

                        // ── Error banner ──────────────────────────────────
                        if let error = errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.red.opacity(0.9))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Button {
                                    errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.red.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                                    )
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        // ── Journey preview card ─────────────────────────
                        JourneyPreviewCard()
                            .padding(.top, 8)

                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                // ── Hidden NavigationLink ─────────────────────────────────
                NavigationLink(
                    destination: Group {
                        if let result = searchResult {
                            ResultsView(
                                response: result,
                                pickupAddress: pickupAddress,
                                destinationAddress: destinationAddress
                            )
                        }
                    },
                    isActive: Binding(
                        get: { searchResult != nil },
                        set: { if !$0 { searchResult = nil } }
                    )
                ) { EmptyView() }

                // ── Search button pinned at bottom ────────────────────────
                Button {
                    Task { await runSearch() }
                } label: {
                    HStack(spacing: 10) {
                        if isSearching {
                            ProgressView().tint(.black)
                            Text("Searching…")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Find Cheaper Rides")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .tracking(0.2)
                        }
                    }
                    .foregroundStyle(canSearch ? Color.black : Color.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                canSearch
                                ? LinearGradient(colors: [Color.white, Color(red: 0.92, green: 0.92, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(canSearch ? 0.2 : 0.08), lineWidth: 0.5)
                    )
                }
                .disabled(!canSearch)
                .animation(.easeInOut(duration: 0.2), value: canSearch)
                .animation(.easeInOut(duration: 0.2), value: isSearching)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @MainActor
    private func fetchCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }

        guard let location = await locManager.requestLocation() else {
            withAnimation { errorMessage = "Could not get your location. Please enter it manually." }
            return
        }

        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        if let placemark = placemarks?.first {
            let name    = placemark.name ?? ""
            let city    = placemark.locality ?? ""
            let state   = placemark.administrativeArea ?? ""
            let address = [name, city, state].filter { !$0.isEmpty }.joined(separator: ", ")
            pickupText    = address
            pickupAddress = address
        } else {
            pickupText    = "Current Location"
            pickupAddress = "Current Location"
        }
    }

    @MainActor
    private func runSearch() async {
        errorMessage = nil
        isSearching  = true
        defer { isSearching = false }
        do {
            searchResult = try await api.findBestPickup(
                pickup: pickupAddress,
                destination: destinationAddress
            )
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// ── Journey Preview Card ─────────────────────────────────────────────────────

private struct JourneyPreviewCard: View {
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Title
            Text("How RideShift works")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.8)

            // Journey visualization
            HStack(spacing: 0) {

                // You
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "figure.stand")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 1.0))
                    }
                    Text("You")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Walking dots
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(animate ? 0.8 : 0.2))
                            .frame(width: 5, height: 5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.12),
                                value: animate
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Cheaper pickup
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "car.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                    }
                    Text("Cheaper pickup")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }

                // Ride dots
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.6, green: 0.9, blue: 0.6).opacity(animate ? 0.8 : 0.2))
                            .frame(width: 8, height: 5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.12 + 0.3),
                                value: animate
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Destination
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    }
                    Text("Destination")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Savings hint
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                Text("A short walk can save you money on every ride")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear { animate = true }
    }
}

// ── Location Manager ─────────────────────────────────────────────────────────

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() async -> CLLocation? {
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.continuation?.resume(returning: locations.first)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}

// ── Dark-themed location field ────────────────────────────────────────────────

private struct DarkLocationField<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var text: String
    var onSelect: (MKLocalSearchCompletion) -> Void
    @ViewBuilder var trailing: () -> Trailing

    @StateObject private var search = LocationSearchService()
    @FocusState  private var isFocused: Bool
    @State private var showSuggestions = false

    init(
        icon: String,
        iconColor: Color = .gray,
        label: String,
        text: Binding<String>,
        onSelect: @escaping (MKLocalSearchCompletion) -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self._text = text
        self.onSelect = onSelect
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(0.8)

                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Enter location")
                            .foregroundColor(.white.opacity(0.25))
                    )
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: text) { newValue in
                        search.queryFragment = newValue
                        showSuggestions = isFocused && !newValue.isEmpty
                    }
                    .onChange(of: isFocused) { focused in
                        showSuggestions = focused && !text.isEmpty
                    }
                }

                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: showSuggestions ? 16 : 20, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: showSuggestions ? 16 : 20, style: .continuous)
                    .stroke(
                        isFocused ? iconColor.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )

            // Suggestions dropdown
            if showSuggestions && !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.suggestions.prefix(5), id: \.self) { suggestion in
                        Button {
                            text = suggestion.title + (suggestion.subtitle.isEmpty ? "" : ", \(suggestion.subtitle)")
                            showSuggestions = false
                            isFocused = false
                            search.queryFragment = ""
                            onSelect(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.4))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if suggestion != search.suggestions.prefix(5).last {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSuggestions)
        .animation(.easeInOut(duration: 0.18), value: search.suggestions.count)
    }
}
