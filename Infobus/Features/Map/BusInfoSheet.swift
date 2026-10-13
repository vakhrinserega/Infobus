//
//  BusInfoSheet.swift
//  Infobus
//
//  A bus's info — plate/name, occupancy, speed — shown as a small anchored
//  popup right at the tapped bus (see BusAnnotationView), not a bottom
//  sheet: there's only ever a couple of fixed fields here, unlike a
//  station's predictions (StationPredictionSheet), which can grow to
//  several routes' worth of arrival times and gets the modal treatment.
//

import SwiftUI

struct BusInfoSheet: View {
    let bus: Bus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bus.name.isEmpty ? "Автобус" : bus.name)
                .font(.headline)
            if let filling = bus.filling {
                // Was `"\(filling)%"` — a plain number with a literal "%"
                // glued on. Xcode's String Catalog checker flags that:
                // percent signs aren't placed/spaced the same way in every
                // language (some put a space before it, some put the sign
                // first), so it has to be locale-formatted rather than
                // hand-assembled. `.percent` expects a 0–1 fraction, not a
                // 0–100 whole number, hence the `/ 100`; `.fractionLength(0)`
                // keeps it a whole percentage regardless of locale.
                Text("Заполненность: \((Double(filling) / 100).formatted(.percent.precision(.fractionLength(0))))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let speed = bus.speed {
                Text("Скорость: \(Int(speed.rounded())) км/ч")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 180, alignment: .leading)
    }
}

#Preview {
    let json = """
    {"name":"123ABC01","direction":45,"lat":51.15,"lon":71.40,"speed":32,"filling":{"percentage":"62"}}
    """.data(using: .utf8)!
    let bus = try! JSONDecoder().decode(Bus.self, from: json)
    return BusInfoSheet(bus: bus)
}
