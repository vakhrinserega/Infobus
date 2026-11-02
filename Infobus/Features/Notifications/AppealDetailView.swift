//
//  AppealDetailView.swift
//  Infobus
//
//  Full text of one appeal and its reply (if any) — just the question and
//  the answer, no thread, matching the "one message, at most one reply"
//  scope of the whole feature (see AppealsStore's header).
//
//  Marks the appeal's current answer as seen the moment this view
//  appears — the list row only shows a status chip, so the badge should
//  stay up until the rider actually opens this and reads the reply.
//

import SwiftUI

struct AppealDetailView: View {
    let appeal: Appeal
    @EnvironmentObject private var appealsStore: AppealsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Вопрос", systemImage: "quote.opening")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    // `appeal.message` is the rider's own text — real
                    // content, not a catalog key, so this stays a plain
                    // `Text(String)` on purpose.
                    Text(appeal.message)
                        .font(.body)
                }

                if let answer = appeal.answer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Ответ", systemImage: "arrowshape.turn.up.left.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(answer)
                            .font(.body)
                    }
                } else {
                    Label("Ожидает ответа", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text("Обращение № \(appeal.id)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appealsStore.markSeen(appeal) }
    }
}

#Preview {
    NavigationStack {
        AppealDetailView(
            appeal: Appeal(
                id: 1042,
                message: "Автобус не отображается на карте.",
                category: nil,
                status: .answered,
                answer: "Спасибо за обращение! Проверили — автобус №12 временно снят с линии на обслуживание, завтра должен появиться снова.",
                createdAt: Date(),
                answeredAt: Date()
            )
        )
    }
    .environmentObject(AppealsStore())
}
