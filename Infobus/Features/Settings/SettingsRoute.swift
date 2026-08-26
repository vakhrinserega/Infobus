//
//  SettingsRoute.swift
//  Infobus
//
//  Value-based destinations pushed on Settings' own NavigationStack. Using a
//  shared path (rather than nested `NavigationLink { destination }` closures)
//  is what lets picking a city clear the whole path in one step and land
//  straight back on Settings, instead of only popping one level at a time.
//

import Foundation

enum SettingsRoute: Hashable {
    case citySelection
    case cityList(Country)
}
