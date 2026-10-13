//
//  RouteMapColor.swift
//  Infobus
//
//  A fixed 5-slot color palette for telling apart up to 5 simultaneously
//  selected routes on the "Карта" tab's map. Slots are assigned per route id
//  and kept stable for as long as that route stays selected (see
//  SelectedRoutesStore) rather than by list position.
//
//  These five hues (and their dark-mode steps) come from validating
//  candidate palettes with the dataviz skill's OKLab-based checker rather
//  than picking plain SwiftUI system colors (.red/.blue/.green/.orange/
//  .purple), which read as garish together and weren't checked for
//  colorblind separation at all. This exact order — blue, orange, aqua,
//  yellow, magenta — passes every adjacent-pair CVD/contrast gate in both
//  light and dark mode; no 5-color subset of the validated 8-hue set clears
//  the stricter *all-pairs* gate (needed since all 5 routes can be on
//  screen at once, not in a fixed sequence), so route number labels (on
//  chips and pins) remain the backup identification, per the palette's own
//  guidance to never rely on hue alone.
//

import SwiftUI
import UIKit

enum RouteMapColor: CaseIterable, Hashable {
    case slot1, slot2, slot3, slot4, slot5

    var color: Color {
        switch self {
        case .slot1: Self.dynamic(light: "#2a78d6", dark: "#3987e5") // синий
        case .slot2: Self.dynamic(light: "#eb6834", dark: "#d95926") // оранжевый
        case .slot3: Self.dynamic(light: "#1baf7a", dark: "#199e70") // бирюзовый
        case .slot4: Self.dynamic(light: "#c98500", dark: "#c98500") // охра/жёлтый — same step both modes for enough contrast on a light map background
        case .slot5: Self.dynamic(light: "#e87ba4", dark: "#d55181") // розовый
        }
    }

    private static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
