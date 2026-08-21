//
//  SearchView.swift
//  Infobus
//
//  Placeholder — search a route between two points.
//

import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            Text("Поиск")
                .foregroundStyle(.secondary)
                .navigationTitle("Поиск")
        }
    }
}

#Preview {
    SearchView()
}
