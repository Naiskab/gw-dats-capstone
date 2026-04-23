import SwiftUI
import MapKit

// ── Dark MapKit view ──────────────────────────────────────────────────────────

struct RouteMapView: UIViewRepresentable {
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        // Dark map appearance
        map.overrideUserInterfaceStyle = .dark
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let originPin = ColoredPin(coordinate: origin, title: "Your location", pinColor: .blue)
        let destPin   = ColoredPin(coordinate: destination, title: "Walk here", pinColor: .green)
        map.addAnnotations([originPin, destPin])

        let request = MKDirections.Request()
        request.source      = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        MKDirections(request: request).calculate { response, _ in
            let overlay = response?.routes.first?.polyline
                ?? MKPolyline(coordinates: [origin, destination], count: 2)
            map.addOverlay(overlay)
            self.zoomToFit(map: map)

        }
    }

    private func zoomToFit(map: MKMapView) {
        let annotations = map.annotations
        guard !annotations.isEmpty else { return }
        var minLat =  90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for ann in annotations {
            minLat = min(minLat, ann.coordinate.latitude)
            maxLat = max(maxLat, ann.coordinate.latitude)
            minLon = min(minLon, ann.coordinate.longitude)
            maxLon = max(maxLon, ann.coordinate.longitude)
        }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:  (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta:  (maxLat - minLat) * 1.7 + 0.002,
                longitudeDelta: (maxLon - minLon) * 1.7 + 0.002
            )
        )
        DispatchQueue.main.async {
            map.setRegion(map.regionThatFits(region), animated: true)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolylineRenderer(polyline: polyline)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth   = 3
            r.lineCap     = .round
            r.lineJoin    = .round
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? ColoredPin else { return nil }
            let id   = pin.pinColor == .blue ? "origin" : "dest"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation     = annotation
            view.canShowCallout = true
            if pin.pinColor == .blue {
                view.markerTintColor = .systemBlue
                view.glyphImage      = UIImage(systemName: "figure.walk")
            } else {
                view.markerTintColor = .systemGreen
                view.glyphImage      = UIImage(systemName: "mappin")
            }
            return view
        }
    }
}

private class ColoredPin: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let pinColor: SwiftUI.Color
    init(coordinate: CLLocationCoordinate2D, title: String, pinColor: SwiftUI.Color) {
        self.coordinate = coordinate
        self.title      = title
        self.pinColor   = pinColor
    }
}

// ── Results View ──────────────────────────────────────────────────────────────

struct ResultsView: View {
    let response: SearchResponse
    let pickupAddress: String
    let destinationAddress: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCandidate: CandidateResult?

    private var originCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: response.origin.lat, longitude: response.origin.lon)
    }
    private var activeCandidate: CandidateResult? { selectedCandidate ?? response.bestCandidate }
    private var activeCoord: CLLocationCoordinate2D? {
        guard let c = activeCandidate else { return nil }
        return CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Map ───────────────────────────────────────────────────
                ZStack(alignment: .topLeading) {
                    if let dest = activeCoord {
                        RouteMapView(origin: originCoord, destination: dest)
                            .frame(height: 260)
                            .ignoresSafeArea(edges: .top)
                    } else {
                        Rectangle()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                            .frame(height: 260)
                    }

                    // Back button
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .padding(.leading, 16)
                    .padding(.top, 56)
                }

                // ── Scrollable results ────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // ── Best pickup hero card ─────────────────────────
                        if let best = response.bestCandidate {
                            BestPickupHero(
                                best: best,
                                originFareCents: response.origin.fareCents
                            )
                            .onTapGesture { selectedCandidate = best }
                        }

                        // ── Origin fare row ───────────────────────────────
                        HStack {
                            HStack(spacing: 10) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 1.0))
                                Text(response.origin.address)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(response.origin.fareCents.map {
                                String(format: "$%.2f", Double($0) / 100)
                            } ?? "n/a")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 4)

                        // Divider
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)

                        // ── All options header ────────────────────────────
                        HStack {
                            Text("All Options")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(response.candidates.count) spots found")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.3))
                        }

                        // ── Candidate rows ────────────────────────────────
                        VStack(spacing: 10) {
                            ForEach(response.candidates.prefix(10)) { candidate in
                                DarkCandidateRow(
                                    candidate: candidate,
                                    isBest: candidate.id == response.bestCandidate?.id,
                                    isSelected: candidate.id == activeCandidate?.id
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35)) {
                                        selectedCandidate = candidate
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .background(Color.black)
            }
        }
        .navigationBarHidden(true)
    }
}

// ── Best Pickup Hero Card ─────────────────────────────────────────────────────

private struct BestPickupHero: View {
    let best: CandidateResult
    let originFareCents: Int?

    var savingsPct: String {
        guard let origin = originFareCents, let fare = best.fareCents, origin > 0 else { return "" }
        let pct = Double(origin - fare) / Double(origin) * 100
        return String(format: "%.0f%% cheaper", pct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                    Text("Best Nearby Pickup")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                Spacer()
                if !savingsPct.isEmpty {
                    Text(savingsPct)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.15))
                        )
                }
            }

            // Big fare + savings
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(best.fareFormatted)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                        Text(best.savingsFormatted)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                    }
                }
                Spacer()
                // Walk info
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 1.0))
                        Text("\(best.walkingMinutes) min")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(String(format: "%.0f m away", best.walkingDistM))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.18, blue: 0.12),
                            Color(red: 0.04, green: 0.08, blue: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.25), lineWidth: 1)
        )
    }
}

// ── Dark Candidate Row ────────────────────────────────────────────────────────

private struct DarkCandidateRow: View {
    let candidate: CandidateResult
    let isBest: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Walk time badge
            VStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(red: 0.4, green: 0.8, blue: 1.0) : .white.opacity(0.3))
                Text("\(candidate.walkingMinutes)m")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color(red: 0.4, green: 0.8, blue: 1.0) : .white.opacity(0.35))
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(String(format: "%.0f m away", candidate.walkingDistM))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    if isBest {
                        Text("BEST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.6, green: 0.9, blue: 0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.15))
                            )
                    }
                }
                Text(candidate.savingsFormatted)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isBest
                        ? Color(red: 0.6, green: 0.9, blue: 0.6)
                        : .white.opacity(0.3))
            }

            Spacer()

            Text(candidate.fareFormatted)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(isBest
                    ? Color(red: 0.6, green: 0.9, blue: 0.6)
                    : .white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected
                    ? Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.08)
                    : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.3)
                        : (isBest
                            ? Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.2)
                            : Color.white.opacity(0.06)),
                    lineWidth: 1
                )
        )
    }
}
