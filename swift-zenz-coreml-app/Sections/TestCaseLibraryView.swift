import SwiftUI
import SwiftData

struct TestCaseLibraryView: View {
    enum EditorMode: Identifiable {
        case add
        case edit(BenchmarkCase)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let testCase):
                return "edit-\(ObjectIdentifier(testCase).hashValue)"
            }
        }
    }

    let cases: [BenchmarkCase]
    let addAction: (String, String) -> Void
    let updateAction: (BenchmarkCase, String, String) -> Void
    let deleteAction: (BenchmarkCase) -> Void
    let resetAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var editorMode: EditorMode?
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            if filteredCases.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(emptyStateMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredCases) { testCase in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(testCase.label)
                                .font(.headline)
                            Spacer(minLength: 8)
                            Text(testCase.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(testCase.kanaPrompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editorMode = .edit(testCase) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Edit") {
                            editorMode = .edit(testCase)
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            deleteAction(testCase)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset to Default Cases", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Test Case Library")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search label or kana")
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .add
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Add Test Case")
            }
        }
        .sheet(item: $editorMode) { mode in
            switch mode {
            case .add:
                TestCaseEditorView(title: "Add Test Case") { label, prompt in
                    addAction(label, prompt)
                }
                .id("add-case-editor")
            case .edit(let testCase):
                TestCaseEditorView(
                    label: testCase.label,
                    kanaPrompt: testCase.kanaPrompt,
                    title: "Edit Test Case"
                ) { label, prompt in
                    updateAction(testCase, label, prompt)
                }
                .id(testCase.persistentModelID)
            }
        }
        .confirmationDialog(
            "Reset test cases?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to default set", role: .destructive) {
                resetAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All existing cases will be replaced by the default kana prompts.")
        }
    }

    private var filteredCases: [BenchmarkCase] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return cases }
        return cases.filter { testCase in
            testCase.label.localizedCaseInsensitiveContains(trimmedQuery) ||
            testCase.kanaPrompt.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var emptyStateMessage: String {
        if cases.isEmpty {
            return "No test cases found. Add your first prompt with the + button."
        }
        if searchText.isEmpty {
            return "No test cases available."
        }
        return "No matches for \"\(searchText)\". Try a different label or kana phrase."
    }
}
