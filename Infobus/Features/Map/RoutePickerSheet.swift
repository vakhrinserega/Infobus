//
//  RoutePickerSheet.swift
//  Infobus
//
//  Add/remove up to 5 routes shown together on the "Карта" tab — mirrors
//  RoutesListView's own search UI so picking a route here feels familiar.
//

import SwiftUI

struct RoutePickerSheet: View {
    let routes: [Route]
    @ObservedObject var store: SelectedRoutesStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var limitReachedRoute: Route?

    var body: some View {
        NavigationStack {
            List(filteredRoutes) { route in
                Button {
                    if !store.toggle(route) {
                        limitReachedRoute = route
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(route.routeNumber)
                            .font(.headline)
                            .frame(minWidth: 40)
                        Text(route.routeName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let slot = store.colorSlot(for: route) {
                            Circle().fill(slot.color).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Номер или название маршрута")
            .navigationTitle("Маршруты на карте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Можно выбрать не более 5 маршрутов", isPresented: limitAlertBinding) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Уберите один из выбранных маршрутов, чтобы добавить «\(limitReachedRoute?.routeNumber ?? "")».")
            }
        }
    }

    private var limitAlertBinding: Binding<Bool> {
        Binding(get: { limitReachedRoute != nil }, set: { if !$0 { limitReachedRoute = nil } })
    }

    private var filteredRoutes: [Route] {
        guard !searchText.isEmpty else { return routes }
        return routes.filter {
            $0.routeNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.routeName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

#Preview {
    RoutePickerSheet(
        routes: [
            Route(id: 1, cityId: 1, busreportRouteId: 1, routeName: "АО «ГазМаш» — пос. «Кирпичный»", routeNumber: "12", location: "")
        ],
        store: SelectedRoutesStore()
    )
}
