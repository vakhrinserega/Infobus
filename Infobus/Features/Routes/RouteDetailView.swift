//
//  RouteDetailView.swift
//  Infobus
//
//  Placeholder destination for tapping a route in the list — the vertical
//  mnemoscheme (stations + live buses, direction tabs, current-station
//  highlight) lands here next, per the design already agreed on.
//

import SwiftUI

struct RouteDetailView: View {
    let route: Route

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(route.routeNumber)
                .font(.largeTitle.bold())
            Text(route.routeName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Мнемосхема маршрута появится здесь")
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
            Spacer()
        }
        .padding()
        .navigationTitle(route.routeNumber)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(route: Route(
            id: 1,
            cityId: 1,
            busreportRouteId: 1,
            routeName: "АО «ГазМаш» — пос. «Кирпичный»",
            routeNumber: "12",
            location: ""
        ))
    }
}
