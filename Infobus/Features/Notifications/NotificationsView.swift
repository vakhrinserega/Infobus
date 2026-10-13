//
//  NotificationsView.swift
//  Infobus
//
//  Placeholder — city announcements / messages.
//

import SwiftUI

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            Text("Уведомления")
                .foregroundStyle(.secondary)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    NotificationsView()
}
