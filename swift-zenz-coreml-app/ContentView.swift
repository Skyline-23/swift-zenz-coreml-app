//
//  ContentView.swift
//  swift-zenz-coreml-app
//
//  Created by Buseong Kim on 11/12/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BenchmarkCase.createdAt) private var storedCases: [BenchmarkCase]
    @State private var log: String = ""
    @State private var isRunning = false
    @State private var env: BenchmarkEnvironment? = nil
    @State private var verbose = false
    @State private var isSharePresented = false
    @State private var showRawLog = false
    @State private var selectedOutputPage = 0
    @State private var outputCardHeight: CGFloat = 220
    @State private var isPresentingCaseLibrary = false
    @State private var showResetConfirmation = false

    private let logScrollID = "log-view"
    private var testCaseStore: TestCaseStore {
        TestCaseStore(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    OverviewSectionView(
                        casesCount: orderedCases.count,
                        envReady: env != nil,
                        verboseOn: verbose
                    )
                }
                .listRowBackground(Color(.systemBackground))
                .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4))

                Section("Environment") {
                    EnvironmentSectionView(verbose: $verbose)
                }
                .listRowBackground(Color(.systemBackground))

                Section("Test Cases") {
                    TestCaseSectionView(
                        totalCount: orderedCases.count,
                        browseAction: { isPresentingCaseLibrary = true },
                        resetAction: { showResetConfirmation = true }
                    )
                }
                .listRowBackground(Color(.systemBackground))

                Section("Benchmarks") {
                    BenchmarkSectionView(
                        casesCount: orderedCases.count,
                        isRunning: isRunning,
                        envReady: env != nil,
                        runAll: { Task { await runAll() } },
                        runShort: { Task { await runShort() } }
                    )
                }
                .listRowBackground(Color(.systemBackground))

                Section("Status & Output") {
                    StatusOutputSectionView(
                        statusEntry: statusEntries.last,
                        outputEntries: outputEntries,
                        selectedPage: $selectedOutputPage,
                        cardHeight: $outputCardHeight
                    )
                }
                .listRowBackground(Color(.systemBackground))
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                .listRowSeparator(.hidden)

                Section("Log Console") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showRawLog.toggle()
                        }
                    } label: {
                        HStack {
                            Text("View Raw Log")
                                .font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .rotationEffect(.degrees(showRawLog ? 180 : 0))
                                .animation(.easeInOut(duration: 0.2), value: showRawLog)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    if showRawLog {
                        LogConsoleSectionView(
                            log: log,
                            logScrollID: logScrollID,
                            isLogEmpty: log.isEmpty,
                            clearAction: { log.removeAll() },
                            shareAction: { isSharePresented = true }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
                    }
                }
                .listRowBackground(Color(.systemBackground))
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("zenz Benchmark Studio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .status) {
                    if isRunning {
                        ProgressView().tint(.primary)
                    }
                }
            }
            .onChange(of: verbose) { GenerationLogConfig.enableVerbose = $0 }
            .onChange(of: outputEntries.count) { newCount in
                let visibleCount = min(newCount, 5)
                if visibleCount == 0 {
                    selectedOutputPage = 0
                } else {
                    selectedOutputPage = min(selectedOutputPage, visibleCount - 1)
                }
                outputCardHeight = 220
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ActivityView(activityItems: [log])
        }
        .sheet(isPresented: $isPresentingCaseLibrary) {
            NavigationStack {
                TestCaseLibraryView(
                    cases: orderedCases,
                    addAction: { label, prompt in
                        Task { @MainActor in addCase(label: label, prompt: prompt) }
                    },
                    updateAction: { testCase, label, prompt in
                        Task { @MainActor in updateCase(testCase, label: label, prompt: prompt) }
                    },
                    deleteAction: { testCase in
                        Task { @MainActor in deleteCase(testCase) }
                    },
                    resetAction: {
                        Task { @MainActor in resetCasesToDefault() }
                    }
                )
            }
        }
        .confirmationDialog(
            "Reset test cases?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to default set", role: .destructive) {
                Task { @MainActor in resetCasesToDefault() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All existing cases will be replaced by the default kana prompts.")
        }
        .task {
            GenerationLogConfig.enableVerbose = verbose
            await prepareEnvironmentIfNeeded()
            await ensureDefaultCasesIfNeeded()
        }
    }

    @MainActor
    private func appendLog(_ text: String) {
        log.append(text.removingKanaMarkers())
    }

    private func prepareEnvironmentIfNeeded() async {
        guard env == nil else { return }
        appendLog("\n[Init] Loading model & tokenizer…\n")
        env = await makeBenchmarkEnvironment()
        appendLog("[Init] Ready.\n")
    }

    @MainActor
    private func resetForNewRun() {
        log.removeAll()
        selectedOutputPage = 0
        outputCardHeight = 220
    }

    private func runAll() async {
        let cases = orderedCases
        guard !cases.isEmpty, let env else { return }
        await MainActor.run {
            resetForNewRun()
            isRunning = true
        }
        defer {
            Task { @MainActor in isRunning = false }
        }
        await MainActor.run { appendLog("\n[RunAll] Started at \(Date())\n") }
        await runSuite(env: env, cases: cases)
        await MainActor.run { appendLog("[RunAll] Finished at \(Date())\n") }
    }

    private func runShort() async {
        let subset = Array(orderedCases.prefix(6))
        guard !subset.isEmpty, let env else { return }
        await MainActor.run {
            resetForNewRun()
            isRunning = true
        }
        defer {
            Task { @MainActor in isRunning = false }
        }
        await MainActor.run { appendLog("\n[RunShort] Started at \(Date())\n") }
        await runSuite(env: env, cases: subset)
        await MainActor.run { appendLog("[RunShort] Finished at \(Date())\n") }
    }

    private func runSuite(env: BenchmarkEnvironment, cases: [BenchmarkCase]) async {
        guard !cases.isEmpty else { return }
        setBenchmarkLogger { line in
            DispatchQueue.main.async {
                self.appendLog(line + "\n")
            }
        }
        for testCase in cases {
            let groupTag = testCase.label
            let kana = encodedPrompt(from: testCase.kanaPrompt)
            guard kana.count > 2 else { continue }
            onLog?("[Case] \(groupTag)")
            await runBenchmarksFor(groupTag: groupTag, kanaInput: kana, env: env)
        }
    }

    private var structuredEntries: [StructuredEntry] {
        let lines = log.components(separatedBy: .newlines)
        var entries: [StructuredEntry] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("=====") {
                var detailLines = [trimmed]
                var rows: [RankingRow] = []
                var lookahead = index + 1
                while lookahead < lines.count {
                    let next = lines[lookahead].trimmingCharacters(in: .whitespacesAndNewlines)
                    if next.isEmpty {
                        lookahead += 1
                        continue
                    }
                    if next.hasPrefix("[") || next.hasPrefix("=====") {
                        break
                    }
                    detailLines.append(next)
                    if let row = parseRankingRow(from: next) {
                        rows.append(row)
                    }
                    lookahead += 1
                }
                let headerLine = detailLines.first ?? trimmed
                let headerParts = parseRankingHeader(from: headerLine)
                let entryID = "ranking-\(index)"
                entries.append(
                    StructuredEntry(
                        id: entryID,
                        icon: "list.number",
                        title: headerParts.title,
                        detail: headerParts.subtitle,
                        accent: .cyan,
                        category: .output,
                        rankingRows: rows
                    )
                )
                index = lookahead
                continue
            } else if trimmed.hasPrefix("[Case]") {
                let name = trimmed.replacingOccurrences(of: "[Case] ", with: "")
                entries.append(StructuredEntry(id: "case-\(index)", icon: "square.grid.2x2", title: "Running case", detail: name, accent: .blue, category: .status, rankingRows: nil))
            } else if trimmed.hasPrefix("[RunAll] Started") {
                entries.append(StructuredEntry(id: "runall-start-\(index)", icon: "play.fill", title: "Full suite started", detail: trimmed, accent: .orange, category: .status, rankingRows: nil))
            } else if trimmed.hasPrefix("[RunAll] Finished") {
                entries.append(StructuredEntry(id: "runall-finish-\(index)", icon: "checkmark.seal.fill", title: "Full suite finished", detail: trimmed, accent: .green, category: .status, rankingRows: nil))
            } else if trimmed.hasPrefix("[RunShort] Started") {
                entries.append(StructuredEntry(id: "runshort-start-\(index)", icon: "bolt.fill", title: "Short run started", detail: trimmed, accent: .yellow, category: .status, rankingRows: nil))
            } else if trimmed.hasPrefix("[RunShort] Finished") {
                entries.append(StructuredEntry(id: "runshort-finish-\(index)", icon: "bolt.circle.fill", title: "Short run finished", detail: trimmed, accent: .teal, category: .status, rankingRows: nil))
            } else if trimmed.hasPrefix("[Init]") {
                entries.append(StructuredEntry(id: "init-\(index)", icon: "shippingbox.fill", title: "Initialization", detail: trimmed, accent: .purple, category: .status, rankingRows: nil))
            }

            index += 1
        }
        return entries
    }

    private var statusEntries: [StructuredEntry] {
        structuredEntries.filter { $0.category == .status }
    }

    private var outputEntries: [StructuredEntry] {
        structuredEntries.filter { $0.category == .output }
    }

    private func parseRankingRow(from line: String) -> RankingRow? {
        let components = line.split(separator: ".", maxSplits: 1)
        guard
            let orderPart = components.first,
            let position = Int(orderPart.trimmingCharacters(in: .whitespaces)),
            components.count == 2
        else { return nil }

        let remainder = components[1].trimmingCharacters(in: .whitespaces)
        let detailParts = remainder.split(separator: ":", maxSplits: 1)
        let label = detailParts.first?.trimmingCharacters(in: .whitespaces) ?? remainder
        let rawDetail = detailParts.count > 1 ? detailParts[1].trimmingCharacters(in: .whitespaces) : ""

        var durationText = ""
        var durationValue: Double?
        var prompt = ""
        var output = ""

        if let range = rawDetail.range(of: " s ") {
            let durationSubstring = rawDetail[..<range.lowerBound]
            let trimmedDuration = durationSubstring.trimmingCharacters(in: .whitespaces)
            durationValue = Double(trimmedDuration)
            if let durationValue {
                durationText = String(format: "%.5f", durationValue)
            } else {
                durationText = trimmedDuration
            }
            let trailing = rawDetail[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let ioParts = trailing.split(separator: ",", maxSplits: 1)
            if let first = ioParts.first {
                prompt = String(first).trimmingCharacters(in: .whitespaces)
            }
            if ioParts.count > 1 {
                output = String(ioParts[1]).trimmingCharacters(in: .whitespaces)
            }
        } else {
            durationText = ""
        }

        return RankingRow(
            position: position,
            label: label,
            duration: durationText,
            input: prompt,
            output: output,
            rawDetail: rawDetail.isEmpty ? remainder : rawDetail
        )
    }

    private func parseRankingHeader(from line: String) -> (title: String, subtitle: String) {
        // Example: "===== Benchmark Ranking for [Case] (fast → slow) ====="
        guard let forRange = line.range(of: "for "), let suffixRange = line.range(of: "(fast") else {
            return ("Ranking Output", line)
        }
        let tagSegment = line[forRange.upperBound..<suffixRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let subtitleRange = line[suffixRange.lowerBound..<line.endIndex]
        let subtitle = subtitleRange
            .replacingOccurrences(of: "=====", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTag = tagSegment.replacingOccurrences(of: "](", with: "] (")
        return ("Ranking • \(cleanedTag)", subtitle.isEmpty ? "fast → slow" : subtitle)
    }

    private var orderedCases: [BenchmarkCase] {
        storedCases
    }

    private func encodedPrompt(from text: String) -> String {
        let trimmed = text.removingKanaMarkers().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\u{EE00}\(trimmed)\u{EE01}"
    }

    @MainActor
    private func addCase(label: String, prompt: String) {
        testCaseStore.addCase(label: label, prompt: prompt)
    }

    @MainActor
    private func updateCase(_ testCase: BenchmarkCase, label: String, prompt: String) {
        testCaseStore.updateCase(testCase, label: label, prompt: prompt)
    }

    @MainActor
    private func deleteCase(_ testCase: BenchmarkCase) {
        testCaseStore.deleteCase(testCase)
    }

    @MainActor
    private func resetCasesToDefault() {
        testCaseStore.resetToDefault(using: storedCases)
    }

    @MainActor
    private func ensureDefaultCasesIfNeeded() {
        testCaseStore.ensureDefaultsIfNeeded(currentCount: storedCases.count)
    }
}
