//
//  MapPointPickerSheet.swift
//  Infobus
//
//  Picks a single point for the Search tab — tap anywhere on the map, or
//  use "Моё местоположение" for the current GPS fix. Matches what the old
//  Objective-C app did (tap a point on the map for search), just without
//  making the rider switch tabs and back to do it — this is a self-
//  contained sheet with its own map.
//
//  The tapped point is reverse-geocoded (Apple's CLGeocoder — no Google SDK
//  in this rewrite) into a short address for display; if that fails for any
//  reason, the raw coordinate is shown instead so picking still works.
//

import SwiftUI
import MapKit

struct MapPointPickerSheet: View {
    let title: String
    let initialCoordinate: CLLocationCoordinate2D?
    let onPick: (CLLocationCoordinate2D, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = UserLocationProvider()
    @State private var cameraPosition: MapCameraPosition
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var addressLabel: String?
    @State private var isResolvingAddress = false

    init(title: String, initialCoordinate: CLLocationCoordinate2D?, onPick: @escaping (CLLocationCoordinate2D, String) -> Void) {
        self.title = title
        self.initialCoordinate = initialCoordinate
        self.onPick = onPick
        _pickedCoordinate = State(initialValue: initialCoordinate)
        _cameraPosition = State(initialValue: initialCoordinate.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 1200, longitudinalMeters: 1200))
        } ?? .automatic)
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let pickedCoordinate {
                        Marker(title, coordinate: pickedCoordinate)
                            .tint(.red)
                    }
                    UserAnnotation()
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    select(coordinate)
                }
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                }
                .overlay(alignment: .top) {
                    if pickedCoordinate == nil {
                        Text("Нажмите на карту, чтобы указать точку")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 12)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            // `title` is a plain `String` (it also feeds the map `Marker`
            // below, which needs that type) — `.navigationTitle(String)`
            // shows it raw with no catalog lookup, which is why this sheet's
            // own title stayed "Откуда"/"Куда" in Russian regardless of the
            // in-app language. Wrapping it here fixes just the nav title.
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear {
                locationProvider.start()
            }
            .onDisappear {
                locationProvider.stop()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                useMyLocation()
            } label: {
                Label("Моё местоположение", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(locationProvider.currentCoordinate == nil)

            if isResolvingAddress {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let addressLabel {
                Text(addressLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard let pickedCoordinate else { return }
                onPick(pickedCoordinate, addressLabel ?? coordinateLabel(pickedCoordinate))
                dismiss()
            } label: {
                Label("Использовать эту точку", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pickedCoordinate == nil)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func useMyLocation() {
        guard let coordinate = locationProvider.currentCoordinate else { return }
        pickedCoordinate = coordinate
        addressLabel = "Моё местоположение"
        isResolvingAddress = false
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D) {
        pickedCoordinate = coordinate
        addressLabel = nil
        isResolvingAddress = true
        Task {
            let label = await reverseGeocode(coordinate)
            // The user may have tapped again (or hit "Моё местоположение")
            // before this resolved — don't clobber a newer pick with a
            // stale address.
            guard pickedCoordinate?.latitude == coordinate.latitude, pickedCoordinate?.longitude == coordinate.longitude else { return }
            addressLabel = label
            isResolvingAddress = false
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            let streetParts = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }
            if !streetParts.isEmpty {
                return streetParts.joined(separator: ", ")
            }
            if let name = placemark.name {
                return name
            }
        }
        return coordinateLabel(coordinate)
    }

    private func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}

#Preview {
    MapPointPickerSheet(title: "Откуда", initialCoordinate: nil) { _, _ in }
}
