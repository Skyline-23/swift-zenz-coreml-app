import SwiftUI

struct TestCaseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kanaPrompt: String
    let onSave: (String, String) -> Void
    let title: String

    init(
        label: String = "",
        kanaPrompt: String = "",
        title: String,
        onSave: @escaping (String, String) -> Void
    ) {
        _label = State(initialValue: label)
        _kanaPrompt = State(initialValue: kanaPrompt)
        self.onSave = onSave
        self.title = title
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. [Greeting]", text: $label)
                        .textInputAutocapitalization(.never)
                }

                Section("Kana Prompt") {
                    TextField("カタカナプロンプト", text: $kanaPrompt, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section {
                    Button("Save") {
                        onSave(label.trimmingCharacters(in: .whitespacesAndNewlines),
                               kanaPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isFormValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !kanaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
