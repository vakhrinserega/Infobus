//
//  StationPredictionSheet.swift
//  Infobus
//
//  A station's arrival predictions across every route that serves it — the
//  station name centered up top, then a two-column table (route, time to
//  arrival) below. Shown as a bottom modal sheet (drag to dismiss), not a
//  small popup, because a busy stop can have predictions for several
//  routes at once and needs room to grow. Compare BusInfoSheet, which shows
//  only a couple of fixed fields and is shown as an anchored popup instead.
//
//  Rows are NOT one-per-bus: the prediction API ties an arrival estimate to
//  a route, not to any particular bus (no госномер/registration on the
//  wire), so a route with two buses inbound shows up as two rows sharing
//  the same route number with two different times — accurate to what the
//  data actually is, rather than implying a bus identity we don't have.
//
//  The route column is a colored capsule badge, not plain text — inspired
//  by a competing app's stop popup that shows which routes serve a stop as
//  colored number chips. When a row's route happens to be one of the up to
//  5 routes currently pinned on the "Карта" tab, its badge matches that
//  route's own line color (via `colorForRoute`), so a rider can connect a
//  prediction row straight back to a line on the map; any other route gets
//  a neutral gray badge rather than an unrelated invented color.
//

import SwiftUI

struct StationPredictionSheet: View {
    let station: Station
    let fetch: () async -> [StationPredictionRow]
    /// Maps a route's `busreportRouteId` to the color it's drawn with on the
    /// map right now, if any. nil (the default) means "not currently on the
    /// map" — that route's badge falls back to neutral gray.
    var colorForRoute: (Int) -> Color? = { _ in nil }
    @State private var rows: [StationPredictionRow]?
    /// Passed through to `Prediction.displayText(locale:)` — see that
    /// property for why it needs an explicit locale rather than just
    /// resolving it itself.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 14) {
            Text(station.name)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            content
        }
        .padding()
        .presentationDetents([.height(280), .medium])
        .presentationDragIndicator(.visible)
        .task {
            rows = await fetch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let rows {
            if rows.isEmpty {
                Text("Нет данных о прибытии")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Маршрут")
                        Spacer()
                        Text("Время до прибытия")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    Divider()

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                HStack {
                                    routeBadge(row)
                                    Spacer()
                                    Text(row.prediction.displayText(locale: locale))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func routeBadge(_ row: StationPredictionRow) -> some View {
        Text(row.routeNumber)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                colorForRoute(row.prediction.routeId) ?? Color(.systemGray2),
                in: Capsule()
            )
    }
}

#Preview {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            StationPredictionSheet(
                station: Station(id: 1, name: "ул. Абая", stationDescription: nil, lat: 51.15, lon: 71.40),
                fetch: {
                    [
                        StationPredictionRow(routeNumber: "12", prediction: Prediction(routeId: 12, prediction: 45)),
                        StationPredictionRow(routeNumber: "12", prediction: Prediction(routeId: 12, prediction: 240)),
                        StationPredictionRow(routeNumber: "7", prediction: Prediction(routeId: 7, prediction: 610)),
                    ]
                },
                colorForRoute: { routeId in routeId == 12 ? .blue : nil }
            )
        }
}
