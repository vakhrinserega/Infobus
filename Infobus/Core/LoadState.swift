//
//  LoadState.swift
//  Infobus
//
//  Shared shape for "loading this from the network" across features —
//  originally lived nested inside SettingsViewModel, pulled out once
//  RoutesListViewModel needed the exact same four states.
//

import Foundation

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}
