//
//  SettingsView.swift
//  Infobus
//
//  Placeholder — city selection, language, about.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Настройки")
                .foregroundStyle(.secondary)
                .navigationTitle("Настройки")
        }
    }
}

#Preview {
    SettingsView()
}
