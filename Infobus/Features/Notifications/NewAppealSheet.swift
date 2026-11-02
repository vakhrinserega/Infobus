//
//  NewAppealSheet.swift
//  Infobus
//
//  Compose form for "Написать обращение" — just a text field and a send
//  button on purpose: no category picker yet (Appeal.category is modeled
//  server-side-ready, just not wired to any UI control here), since a
//  rider with a bus problem wants to type it and move on, not fill out a
//  form.
//

import SwiftUI

struct NewAppealSheet: View {
    let city: City
    @ObservedObject var store: AppealsStore

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .focused($isFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Опишите ваш вопрос или проблему")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    if let submitError = store.submitError {
                        // `submitError` is a plain `String` set on the
                        // store — `Text(String)` wouldn't localize it;
                        // same `LocalizedStringKey` re-wrap used
                        // everywhere else this pattern shows up.
                        Text(LocalizedStringKey(submitError))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Новое обращение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Отправить", action: submit)
                            .disabled(trimmedText.isEmpty)
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func submit() {
        let message = trimmedText
        guard !message.isEmpty else { return }
        Task {
            if await store.submit(message: message, city: city) {
                dismiss()
            }
        }
    }
}

#Preview {
    NewAppealSheet(city: City(id: 13, name: "Кокшетау", serviceURL: "https://example.com"), store: AppealsStore())
}
