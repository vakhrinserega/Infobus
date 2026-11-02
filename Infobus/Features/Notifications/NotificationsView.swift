//
//  NotificationsView.swift
//  Infobus
//
//  Two unrelated things share this one tab, each with its own backend:
//
//  "Объявления" — a single admin-authored, city-wide message from the
//  main infobus.kz API (`CityInfo.message`/`displayMessage`, see
//  AnnouncementStore). Everyone with this city selected sees the same
//  thing; there's nothing to page through, just one message or none.
//
//  "Мои обращения" — this device's own support requests, answered one at
//  a time (see AppealsStore's header), backed by a separate per-city
//  Google Apps Script + Telegram bot, not infobus.kz itself.
//
//  Both stores' fetching/polling and unseen-badge bookkeeping live at the
//  app root (ContentView) rather than here, so the badge on this tab's
//  own icon keeps working while some other tab is on screen — this view
//  just displays whatever they currently have, and clears each one's
//  contribution to the badge as its content is actually seen.
//
//  Each of the two sections ALSO carries its own small marker next to its
//  own title (see `announcementsLabel`/`appealsLabel`/`UnreadMarker`) —
//  the shared tab badge only says "something arrived somewhere in here",
//  which isn't enough once a rider has collapsed one of these sections:
//  without a marker on the section itself they'd have to expand both just
//  to find out which one actually changed. "Мои обращения" goes one level
//  further still — the SAME marker shows up again on the one specific
//  `AppealRow` that actually has the new reply, since a section-level
//  marker alone doesn't say which of several appeals it was.
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @EnvironmentObject private var announcementStore: AnnouncementStore
    @EnvironmentObject private var appealsStore: AppealsStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var isComposingAppeal = false
    /// Persisted (not just per-session) — a rider who collapses "Объявления"
    /// because they've already read it shouldn't have it pop back open
    /// next time they open this tab.
    @AppStorage("notifications.isAnnouncementsExpanded") private var isAnnouncementsExpanded = true
    @AppStorage("notifications.isAppealsExpanded") private var isAppealsExpanded = true

    var body: some View {
        NavigationStack {
            content
                // No navigation bar/title — same convention as the other
                // root tabs (Карта, Маршруты, Поиск): the tab bar icon
                // below already names this screen.
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $isComposingAppeal) {
                    if let city = cityStore.selectedCity {
                        NewAppealSheet(city: city, store: appealsStore)
                    }
                }
        }
        .onAppear(perform: markAnnouncementSeenIfNeeded)
        .onChange(of: announcementStore.message) { _, _ in markAnnouncementSeenIfNeeded() }
        // Expanding "Объявления" is itself a "the rider just read this"
        // moment, same as the tab merely appearing while it was already
        // expanded — without this, collapsing it and reopening the tab
        // would never re-offer a chance to mark it seen.
        .onChange(of: isAnnouncementsExpanded) { _, expanded in
            if expanded { markAnnouncementSeenIfNeeded() }
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
            List {
                Section {
                    DisclosureGroup(isExpanded: $isAnnouncementsExpanded) {
                        announcementSection
                    } label: {
                        announcementsLabel
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $isAppealsExpanded) {
                        appealsSection
                    } label: {
                        appealsLabel
                    }
                }
            }
            .listStyle(.insetGrouped)
            // `List` is UIKit-table-bridged, and (like `.navigationTitle`
            // on an already-mounted `NavigationStack` — see SettingsView)
            // doesn't reliably re-resolve its rows' `LocalizedStringKey`
            // content from an environment-only change while this tab
            // stays mounted in the background. Keying it to the current
            // language forces a full rebuild the moment it changes,
            // instead of leaving "Объявления"/"Мои обращения" stuck in
            // whatever language was active when this tab was first shown.
            .id(settings.language)
        }
    }

    // MARK: - Section headers

    /// A plain dot — not a count, since there's only ever at most one
    /// active announcement at a time — next to the title whenever it
    /// hasn't been seen yet, so collapsing this section doesn't hide the
    /// fact that something's waiting there.
    private var announcementsLabel: some View {
        HStack(spacing: 6) {
            Label("Объявления", systemImage: "megaphone")
                .font(.headline)
            if announcementStore.hasUnseenAnnouncement {
                UnreadMarker(count: nil)
            }
        }
    }

    /// Same idea as `announcementsLabel`, but with the actual unseen-reply
    /// count — unlike announcements, more than one appeal can come back
    /// answered at once.
    private var appealsLabel: some View {
        HStack(spacing: 6) {
            Label("Мои обращения", systemImage: "envelope")
                .font(.headline)
            if appealsStore.unseenAnsweredCount > 0 {
                UnreadMarker(count: appealsStore.unseenAnsweredCount)
            }
        }
    }

    // MARK: - Объявления

    @ViewBuilder
    private var announcementSection: some View {
        switch announcementStore.loadState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .failed(let errorMessage):
            VStack(alignment: .leading, spacing: 6) {
                // `errorMessage` is a plain `String` set on the store —
                // `Text(String)` never looks anything up in
                // Localizable.xcstrings, so this needs the same
                // `LocalizedStringKey` re-wrap used everywhere else this
                // pattern shows up.
                Text(LocalizedStringKey(errorMessage))
                    .foregroundStyle(.secondary)
                Button("Повторить") {
                    Task {
                        guard let city = cityStore.selectedCity else { return }
                        await announcementStore.retry(for: city)
                    }
                }
            }
        case .loaded:
            if let message = announcementStore.message {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Объявление", systemImage: "megaphone.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    // `message` is the city's own admin-authored text —
                    // real content, not a catalog key, so this stays a
                    // plain `Text(String)` on purpose.
                    Text(message)
                }
                .padding(.vertical, 4)
            } else {
                Text("Нет активных объявлений")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Мои обращения

    @ViewBuilder
    private var appealsSection: some View {
        switch appealsStore.loadState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .failed(let errorMessage):
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(errorMessage))
                    .foregroundStyle(.secondary)
                Button("Повторить") {
                    Task {
                        guard let city = cityStore.selectedCity else { return }
                        await appealsStore.retry(for: city)
                    }
                }
            }
        case .loaded:
            if !appealsStore.isAvailableForCity {
                Text("Обращения пока недоступны для этого города")
                    .foregroundStyle(.secondary)
            } else {
                if appealsStore.appeals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Нет обращений")
                        Text("Если у вас есть вопрос или жалоба, напишите нам — ответ появится здесь.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(appealsStore.appeals) { appeal in
                        NavigationLink {
                            AppealDetailView(appeal: appeal)
                        } label: {
                            AppealRow(appeal: appeal, isUnseen: appealsStore.isUnseen(appeal))
                        }
                    }
                }
                Button {
                    isComposingAppeal = true
                } label: {
                    Label("Написать обращение", systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// An active announcement only counts as "seen" once "Объявления" is
    /// actually expanded on screen — called on first appearance, again
    /// whenever the message changes while this tab is already on screen,
    /// and again whenever the section itself gets expanded. Opening this
    /// tab while that section is still collapsed must NOT clear its
    /// marker (see `announcementsLabel`) before the rider has had a real
    /// chance to read it.
    private func markAnnouncementSeenIfNeeded() {
        guard isAnnouncementsExpanded,
              let city = cityStore.selectedCity,
              announcementStore.message != nil else { return }
        announcementStore.markSeen(cityId: city.id)
    }
}

/// One row in "Мои обращения" — the question's first line plus a status
/// chip, same two statuses ChatGPT's own mockup used ("Ожидает ответа" /
/// "Ответ получен"), tap opens AppealDetailView for the full text.
///
/// `isUnseen` is what the section-level badge (see `appealsLabel`) was
/// missing on its own: that badge only ever said "something in here has
/// a new reply," which wasn't enough once there was more than one appeal
/// in the list — opening "Мои обращения" still left the rider guessing
/// which row it actually was. The same red marker used for the section
/// badges now shows up on THIS specific row instead.
private struct AppealRow: View {
    let appeal: Appeal
    let isUnseen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if isUnseen {
                    UnreadMarker(count: nil)
                        .padding(.top, 5)
                }
                Text(appeal.message)
                    .lineLimit(1)
                    .fontWeight(isUnseen ? .semibold : .regular)
                Spacer()
                statusChip
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text(appeal.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch appeal.status {
        case .new:
            Text("Ожидает ответа")
                .foregroundStyle(.orange)
        case .answered:
            Text("Ответ получен")
                .foregroundStyle(.green)
        }
    }
}

/// Small red "something's new here" marker placed next to a collapsed
/// section's own title — the shared tab-icon badge says *something*
/// arrived; this says *which* section it's in, without needing to
/// expand either one to check. `count == nil` renders a plain dot (used
/// for "Объявления", which never has more than one active message to
/// count); a number renders inside a pill (used for "Мои обращения",
/// which can have more than one unseen reply waiting at once).
private struct UnreadMarker: View {
    let count: Int?

    var body: some View {
        if let count, count > 0 {
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
        } else {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(SelectedCityStore())
        .environmentObject(AnnouncementStore())
        .environmentObject(AppealsStore())
        .environmentObject(AppSettingsStore())
}
