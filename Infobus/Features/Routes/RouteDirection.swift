//
//  RouteDirection.swift
//  Infobus
//
//  A route's two independently-sequenced station orderings (see
//  RouteStationLink's header) surfaced as the mnemoscheme's direction tabs.
//

import SwiftUI

enum RouteDirection: Hashable {
    case forward
    case backward

    var displayName: LocalizedStringKey {
        switch self {
        case .forward: "Туда"
        case .backward: "Обратно"
        }
    }
}
