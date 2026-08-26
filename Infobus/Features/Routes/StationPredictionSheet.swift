//
//  StationPredictionSheet.swift
//  Infobus
//
//  Tap-for-detail popup for a station on the mnemoscheme — shown both for
//  stations with an inline ETA already visible (more detail) and ones
//  without any prediction data at all.
//

import SwiftUI

struct StationPredictionSheet: View {
    let stop: RouteStop
    let predictions: [Prediction]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if predictions.isEmpty {
                    Text("Нет данных о прибытии для этой остановки.")
                        .foregroundStyle(.secondary)
                } else {
                    let sorted = predictions.sorted { $0.prediction < $1.prediction }
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, prediction in
                        HStack {
                            Text("Автобус \(index + 1)")
                            Spacer()
                            Text("≈ \(Int(prediction.prediction.rounded())) мин")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(stop.station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    StationPredictionSheet(
        stop: RouteStop(
            station: Station(id: 1, name: "ул. Абая", stationDescription: nil, lat: 51.15, lon: 71.40),
            sequenceNumber: 1,
            fraction: 0.2
        ),
        predictions: [Prediction(routeId: 12, prediction: 4), Prediction(routeId: 12, prediction: 15)]
    )
}
