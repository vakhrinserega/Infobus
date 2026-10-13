//
//  SelectedRoutesStore.swift
//  Infobus
//
//  Which routes are pinned on the "Карта" tab right now — up to 5, order
//  preserved for chip display. Persisted per (country, city) the same way
//  CityDataCache is keyed, to avoid the same cross-country city-id collision
//  risk already fixed elsewhere (city ids are only unique per-country).
//
//  Each selected route keeps a stable color slot for as long as it stays
//  selected, assigned by lowest-free-slot rather than by position in the
//  list — so removing route B out of [A, B, C] never changes C's color, the
//  way a naive "color = index" scheme would.
//

import Foundation
import Combine

@MainActor
final class SelectedRoutesStore: ObservableObject {
    static let maxSelectedRoutes = RouteMapColor.allCases.count

    @Published private(set) var selectedRouteIds: [Int] = []
    @Published private(set) var colorSlotByRouteId: [Int: RouteMapColor] = [:]

    private let defaults: UserDefaults
    private var storageKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(country: Country, city: City) {
        let key = Self.key(country: country, city: city)
        storageKey = key
        let ids = defaults.array(forKey: key) as? [Int] ?? []
        selectedRouteIds = Array(ids.prefix(Self.maxSelectedRoutes))
        reassignSlots()
    }

    var isFull: Bool { selectedRouteIds.count >= Self.maxSelectedRoutes }

    func isSelected(_ route: Route) -> Bool {
        selectedRouteIds.contains(route.busreportRouteId)
    }

    func colorSlot(for route: Route) -> RouteMapColor? {
        colorSlotByRouteId[route.busreportRouteId]
    }

    /// Adds the route if there's room and it isn't already selected, or
    /// removes it if it is. Returns false only when trying to add past the
    /// 5-route limit, so the caller can tell the difference between "toggled
    /// off" and "couldn't add".
    @discardableResult
    func toggle(_ route: Route) -> Bool {
        let id = route.busreportRouteId
        if let index = selectedRouteIds.firstIndex(of: id) {
            selectedRouteIds.remove(at: index)
        } else {
            guard !isFull else { return false }
            selectedRouteIds.append(id)
        }
        reassignSlots()
        persist()
        return true
    }

    func remove(routeId: Int) {
        selectedRouteIds.removeAll { $0 == routeId }
        reassignSlots()
        persist()
    }

    private func reassignSlots() {
        var updated: [Int: RouteMapColor] = [:]
        for id in selectedRouteIds {
            if let existing = colorSlotByRouteId[id] {
                updated[id] = existing
            }
        }
        var usedSlots = Set(updated.values)
        for id in selectedRouteIds where updated[id] == nil {
            if let freeSlot = RouteMapColor.allCases.first(where: { !usedSlots.contains($0) }) {
                updated[id] = freeSlot
                usedSlots.insert(freeSlot)
            }
        }
        colorSlotByRouteId = updated
    }

    private func persist() {
        guard let storageKey else { return }
        defaults.set(selectedRouteIds, forKey: storageKey)
    }

    private static func key(country: Country, city: City) -> String {
        "SelectedRoutesStore-country-\(country.id)-city-\(city.id)"
    }
}
