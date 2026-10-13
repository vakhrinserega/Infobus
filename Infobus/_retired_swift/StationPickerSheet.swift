//
//  StationPickerSheet.swift
//  Infobus
//
//  A searchable station list — used by the Search tab for picking "откуда"
//  and "куда". Mirrors RoutePickerSheet's own search UI for consistency.
//

import SwiftUI

struct StationPickerSheet: View {
    let title: String
    let stations: [Station]
    let onSelect: (Station) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredStations) { station in
                Button {
                    onSelect(station)
                    dismiss()
                } label: {
                    Text(station.name)
                        .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Название остановки")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private var filteredStations: [Station] {
        guard !searchText.isEmpty else { return stations }
        return stations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

#Preview {
    StationPickerSheet(
        title: "Откуда",
        stations: [
            Station(id: 1, name: "ул. Абая", stationDescription: nil, lat: 51.15, lon: 71.40),
            Station(id: 2, name: "пр. Тәуелсіздік", stationDescription: nil, lat: 51.16, lon: 71.41)
        ],
        onSelect: { _ in }
    )
}
