//
//  MapView.swift
//  Infobus
//
//  Placeholder — live map with up to 5 active routes.
//

import SwiftUI

struct MapView: View {
    var body: some View {
        NavigationStack {
            Text("Карта")
                .foregroundStyle(.secondary)
                .navigationTitle("Карта")
        }
    }
}

#Preview {
    MapView()
}
