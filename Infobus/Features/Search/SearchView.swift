//
//  SearchView.swift
//  Infobus
//
//  "Поиск" tab — pick a departure and destination point and see which
//  route(s) connect them, via the old `pathsbwpoints` endpoint.
//
//  Points are picked by tapping a self-contained map sheet (or "Моё
//  местоположение" for the current GPS fix) — see MapPointPickerSheet —
//  rather than from a station list: the endpoint takes raw coordinates and
//  the backend itself works out which nearby stops to walk to, matching how
//  the old app's own map-tap search worked. A station picker would only
//  have narrowed that down artificially.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @StateObject private var viewModel = SearchViewModel()
    @State private var pickerTarget: MapPointTarget?

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: cityStore.selectionKey) {
            viewModel.reset()
        }
        .sheet(item: $pickerTarget) { target in
            MapPointPickerSheet(
                title: target.title,
                initialCoordinate: target.isFrom ? viewModel.fromPoint?.coordinate : viewModel.toPoint?.coordinate
            ) { coordinate, label in
                let point = SearchPoint(coordinate: coordinate, label: label)
                if target.isFrom {
                    viewModel.fromPoint = point
                } else {
                    viewModel.toPoint = point
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if cityStore.selectedCity == nil {
            ContentUnavailableView(
                "Город не выбран",
                systemImage: "mappin.slash",
                description: Text("Выберите город на вкладке «Настройки».")
            )
        } else {
            VStack(spacing: 0) {
                form
                Divider()
                results
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 10) {
            pointRow(
                title: "Откуда",
                point: viewModel.fromPoint,
                systemImage: "circle.fill",
                tint: .green
            ) {
                pickerTarget = .from
            }
            pointRow(
                title: "Куда",
                point: viewModel.toPoint,
                systemImage: "mappin.circle.fill",
                tint: .red
            ) {
                pickerTarget = .to
            }

            HStack {
                Button("Сбросить") {
                    viewModel.reset()
                }
                .disabled(viewModel.fromPoint == nil && viewModel.toPoint == nil)

                Spacer()

                Button {
                    guard let city = cityStore.selectedCity else { return }
                    Task { await viewModel.search(city: city) }
                } label: {
                    Label("Найти", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.fromPoint == nil || viewModel.toPoint == nil)
            }
        }
        .padding()
    }

    private func pointRow(
        title: String,
        point: SearchPoint?,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    // `title`/`point?.label` are plain `String`s (the row is
                    // shared between "Откуда" and "Куда"), so `Text(_:)` here
                    // would use the raw-string initializer and never look
                    // anything up in Localizable.xcstrings — this was exactly
                    // why these two stayed in Russian regardless of the
                    // in-app language. Re-wrapping in `LocalizedStringKey`
                    // makes it look up the current string as a catalog key
                    // again; a real address in `point.label` just won't
                    // match one and displays unchanged, which is what we
                    // want for that dynamic case anyway.
                    Text(LocalizedStringKey(title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(point?.label ?? "Укажите точку на карте"))
                        .foregroundStyle(point == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch viewModel.resultsState {
        case .idle:
            ContentUnavailableView(
                "Найдите маршрут",
                systemImage: "arrow.triangle.swap",
                description: Text("Укажите на карте, откуда и куда вы едете.")
            )
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Ошибка поиска", systemImage: "exclamationmark.triangle")
            } description: {
                // Same fix as pointRow above — `message` is a `String` set
                // on the view model, `Text(String)` never localized it.
                Text(LocalizedStringKey(message))
            }
        case .loaded(let items):
            if items.isEmpty {
                ContentUnavailableView("Автобусом отсюда добраться не получилось найти", systemImage: "bus")
            } else {
                List(items) { item in
                    SearchResultRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }
}

private enum MapPointTarget: Identifiable {
    case from, to

    var id: Self { self }

    var isFrom: Bool { self == .from }

    var title: String {
        switch self {
        case .from: return "Откуда"
        case .to: return "Куда"
        }
    }
}

private struct SearchResultRow: View {
    let item: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.route.number)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                Text(item.route.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(item.departureStop.name)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(item.arrivalStop.name)
            }
            .font(.subheadline)
            Text("\(item.numStops) ост.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchView()
        .environmentObject(SelectedCityStore())
}
