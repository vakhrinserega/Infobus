//
//  RoutesListView.swift
//  Infobus
//
//  Placeholder — list of routes/stations for the selected city.
//

import SwiftUI

struct RoutesListView: View {
    var body: some View {
        NavigationStack {
            Text("Маршруты")
                .foregroundStyle(.secondary)
                .navigationTitle("Маршруты")
        }
    }
}

#Preview {
    RoutesListView()
}
