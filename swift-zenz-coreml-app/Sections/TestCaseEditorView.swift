import SwiftUI

struct TestCaseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kanaPrompt: String
    @State private var expectedOutput: String
    let onSave: (String, String, String) -> Void
    let title: String

    init(
        label: String = "",
        kanaPrompt: String = "",
        expectedOutput: String = "",
        title: String,
        onSave: @escaping (String, String, String) -> Void
    ) {
        _label = State(initialValue: label)
        _kanaPrompt = State(initialValue: kanaPrompt)
        _expectedOutput = State(initialValue: expectedOutput)
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

                Section("Expected Output") {
                    TextField("予想される応答（必須）", text: $expectedOutput, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Save") {
                        onSave(label.trimmingCharacters(in: .whitespacesAndNewlines),
                               kanaPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                               expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
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
        !kanaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
