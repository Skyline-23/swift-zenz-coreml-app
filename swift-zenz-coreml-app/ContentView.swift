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
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BenchmarkCase.createdAt) private var storedCases: [BenchmarkCase]
    @State private var log: String = ""
    @State private var isRunning = false
    @State private var env: BenchmarkEnvironment? = nil
    @State private var verbose = false
    @State private var includeSyncBenchmarks = false
    @State private var selectedStatelessModels: Set<ZenzStatelessModelVariant> = []
    @State private var selectedStatefulModels: Set<ZenzStatefulModelVariant> = []
    @State private var loadedConfiguration = ModelLoadConfiguration.empty
    @State private var isSharePresented = false
    @State private var showRawLog = false
    @State private var selectedOutputPage = 0
    @State private var outputCardResetToken = 0
    @State private var isPresentingCaseLibrary = false
    @State private var showResetConfirmation = false
    @StateObject private var memoryMonitor = MemoryUsageMonitor()
    @State private var hudPosition: CGPoint? = nil
    @State private var hudDragOffset: CGSize = .zero
    @State private var hudContainerSize: CGSize = .zero
    @State private var isMemoryExpanded = false
    @State private var hudCompactSize: CGSize = CGSize(width: 140, height: 50)
    @State private var hudExpandedSize: CGSize = CGSize(width: 330, height: 220)

    private let logScrollID = "log-view"
    private let memoryHUDAnimation = Animation.interpolatingSpring(
        mass: 0.28,
        stiffness: 135,
        damping: 7.8,
        initialVelocity: 0.65
    )
    private let hudSnapAnimation = Animation.spring(
        response: 0.24,
        dampingFraction: 0.92,
        blendDuration: 0.08
    )
    private let enableMemoryMonitoring = true
    private let enableHUDResnapDuringLayout = true
    private var testCaseStore: TestCaseStore {
        TestCaseStore(modelContext: modelContext)
    }

    var body: some View {
        GeometryReader { rootGeometry in
            let rootFrame = rootGeometry.frame(in: .global)
            let rootSafeAreaInsets = rootGeometry.safeAreaInsets
            ZStack {
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
                            EnvironmentSectionView(
                                verbose: $verbose,
                                includeSyncBenchmarks: $includeSyncBenchmarks,
                                statelessSelection: $selectedStatelessModels,
                                statefulSelection: $selectedStatefulModels
                            )
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

                        if !benchmarkAverages.isEmpty {
                            Section("Benchmark Averages") {
                                RankingAverageSectionView(averages: benchmarkAverages)
                            }
                            .listRowBackground(Color(.systemBackground))
                        }

                        Section("Status & Output") {
                            StatusOutputSectionView(
                                statusEntry: statusEntries.last,
                                outputEntries: outputEntries,
                                selectedPage: $selectedOutputPage,
                                heightResetToken: outputCardResetToken
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
                    // HUD overlay removed from here.
                    .onChange(of: verbose) { GenerationLogConfig.enableVerbose = $0 }
                    .onChange(of: selectedStatelessModels) { _ in
                        Task { await prepareEnvironmentIfNeeded(force: true) }
                    }
                    .onChange(of: selectedStatefulModels) { _ in
                        Task { await prepareEnvironmentIfNeeded(force: true) }
                    }
                    .onChange(of: outputEntries.count) { newCount in
                        let visibleCount = min(newCount, 5)
                        if visibleCount == 0 {
                            selectedOutputPage = 0
                        } else {
                            selectedOutputPage = min(selectedOutputPage, visibleCount - 1)
                        }
                        outputCardResetToken &+= 1
                    }
                }

                GeometryReader { overlayProxy in
                    let mergedInsets = mergeSafeAreaInsets(overlayProxy.safeAreaInsets, rootSafeAreaInsets)
                    floatingMemoryHUD(
                        in: rootFrame.size,
                        safeAreaInsets: mergedInsets
                    )
                    .frame(width: rootFrame.size.width, height: rootFrame.size.height, alignment: .topLeading)
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ActivityView(activityItems: [log])
            }
            .sheet(isPresented: $isPresentingCaseLibrary) {
                NavigationStack {
                    TestCaseLibraryView(
                        cases: orderedCases,
                        addAction: { label, prompt, expected in
                            Task { @MainActor in addCase(label: label, prompt: prompt, expected: expected) }
                        },
                        updateAction: { testCase, label, prompt, expected in
                            Task { @MainActor in
                                updateCase(
                                    testCase,
                                    label: label,
                                    prompt: prompt,
                                    expected: expected
                                )
                            }
                        },
                        deleteAction: { testCase in
                            Task { @MainActor in deleteCase(testCase) }
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
                if enableMemoryMonitoring {
                    await memoryMonitor.start()
                }
                await prepareEnvironmentIfNeeded(force: false)
                await ensureDefaultCasesIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                guard enableMemoryMonitoring else { return }
                switch phase {
                case .active:
                    Task { await memoryMonitor.start() }
                case .background, .inactive:
                    Task { await memoryMonitor.stop() }
                @unknown default:
                    break
                }
            }
            .frame(width: rootFrame.size.width, height: rootFrame.size.height)
        }
    }

    @MainActor
    private func appendLog(_ text: String) {
        log.append(text.removingKanaMarkers())
    }

    private var currentModelSelection: ModelLoadConfiguration {
        ModelLoadConfiguration(
            stateless: selectedStatelessModels,
            stateful: selectedStatefulModels
        )
    }

    private func prepareEnvironmentIfNeeded(force: Bool) async {
        let desiredConfig = currentModelSelection

        if desiredConfig.isEmpty {
            await MainActor.run {
                if env != nil {
                    env = nil
                    appendLog("\n[Init] Cleared environment: No Core ML models selected.\n")
                }
                loadedConfiguration = .empty
            }
            return
        }

        let needsReload = force || env == nil || loadedConfiguration != desiredConfig
        guard needsReload else { return }

        await MainActor.run {
            appendLog("\n[Init] Loading tokenizer + \(desiredConfig.summaryDescription)…\n")
        }

        let loadedEnv = await Task.detached(priority: .userInitiated) {
            await makeBenchmarkEnvironment(config: desiredConfig)
        }.value

        guard let loadedEnv else {
            await MainActor.run {
                env = nil
                loadedConfiguration = .empty
                appendLog("[Init] Failed: Selected models are unavailable.\n")
            }
            return
        }

        await MainActor.run {
            env = loadedEnv
            loadedConfiguration = desiredConfig
            appendLog("[Init] Ready (\(loadedEnv.statelessModels.count) stateless / \(loadedEnv.statefulModels.count) stateful).\n")
        }
    }

    private func floatingMemoryHUD(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        let center = resolvedHUDCenter(in: containerSize, safeAreaInsets: safeAreaInsets)
        let hudButtonShape = RoundedRectangle(
            cornerRadius: isMemoryExpanded ? 28 : 18,
            style: .continuous
        )
        let hudButton = Button {
            withAnimation(memoryHUDAnimation) {
                isMemoryExpanded.toggle()
            }
        } label: {
            MemoryUsageHUD(
                currentMegabytes: memoryMonitor.currentMegabytes,
                samples: memoryMonitor.samples,
                isExpanded: isMemoryExpanded
            )
                .foregroundStyle(.primary)
                .opacity(memoryMonitor.currentMegabytes == nil ? 0.5 : 1)
                .padding(.horizontal, isMemoryExpanded ? 18 : 8)
                .padding(.vertical, isMemoryExpanded ? 15 : 5)
                .liquidGlassTile(tint: .cyan.opacity(0.75), shape: hudButtonShape)
        }
        .buttonStyle(.plain)

        let resnapToEdges: () -> Void = {
            requestHUDResnap(with: safeAreaInsets)
        }

        let constrainedHUDButton = hudButton
            .frame(
                width: isMemoryExpanded
                    ? hudExpandedDisplayWidth(in: containerSize, safeAreaInsets: safeAreaInsets)
                    : nil,
                alignment: .leading
            )

        return constrainedHUDButton
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: MemoryHUDSizePreferenceKey.self, value: proxy.size)
                }
            )
            .position(center)
            .onPreferenceChange(MemoryHUDSizePreferenceKey.self) { newValue in
                Task { @MainActor in updateHUDMeasuredSize(newValue) }
            }
            .animation(memoryHUDAnimation, value: isMemoryExpanded)
            .animation(memoryHUDAnimation, value: hudExpandedSize)
            .animation(memoryHUDAnimation, value: hudCompactSize)
            .animation(hudSnapAnimation, value: hudPosition)
            .highPriorityGesture(dragGesture(in: containerSize, safeAreaInsets: safeAreaInsets))
            .task {
                await MainActor.run {
                    updateHUDContainerSizeIfNeeded(containerSize)
                }
            }
            .onChange(of: safeAreaInsets) { newValue in
                requestHUDResnap(with: newValue)
            }
            .onChange(of: containerSize) { newValue in
                updateHUDContainerSizeIfNeeded(newValue)
                requestHUDResnap(with: safeAreaInsets)
            }
            .onChange(of: isMemoryExpanded) { _ in
                requestHUDResnap(with: safeAreaInsets)
            }
            .onChange(of: hudCompactSize) { _ in
                guard !isMemoryExpanded else { return }
                resnapToEdges()
            }
            .onChange(of: hudExpandedSize) { _ in
                guard isMemoryExpanded else { return }
                resnapToEdges()
            }
    }

    @MainActor
    private func updateHUDContainerSizeIfNeeded(_ newSize: CGSize) {
        guard hudContainerSize != newSize else { return }
        hudContainerSize = newSize
    }

    @MainActor
    private func updateHUDMeasuredSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        if isMemoryExpanded {
            let delta = abs(hudExpandedSize.width - newSize.width) + abs(hudExpandedSize.height - newSize.height)
            guard delta > 0.5 else { return }
            hudExpandedSize = newSize
        } else {
            let delta = abs(hudCompactSize.width - newSize.width) + abs(hudCompactSize.height - newSize.height)
            guard delta > 0.5 else { return }
            hudCompactSize = newSize
        }
    }

    private func dragGesture(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                hudDragOffset = value.translation
            }
            .onEnded { value in
                snapHUDPosition(in: containerSize, translation: value.translation, safeAreaInsets: safeAreaInsets)
            }
    }

    private func resolvedHUDCenter(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        let base = hudPosition ?? defaultHUDCenter(in: containerSize, safeAreaInsets: safeAreaInsets)
        let current = CGPoint(
            x: base.x + hudDragOffset.width,
            y: base.y + hudDragOffset.height
        )
        return clampHUDPoint(current, in: containerSize, safeAreaInsets: safeAreaInsets)
    }

    private func snapHUDPosition(in containerSize: CGSize, translation: CGSize, safeAreaInsets: EdgeInsets) {
        let start = hudPosition ?? defaultHUDCenter(in: containerSize, safeAreaInsets: safeAreaInsets)
        var next = CGPoint(
            x: start.x + translation.width,
            y: start.y + translation.height
        )
        next = clampHUDPoint(next, in: containerSize, safeAreaInsets: safeAreaInsets)

        let horizontalRange = hudHorizontalRange(in: containerSize, safeAreaInsets: safeAreaInsets)
        let verticalRange = hudVerticalRange(in: containerSize.height, safeAreaInsets: safeAreaInsets)
        let leftAnchor = horizontalRange.lowerBound
        let rightAnchor = horizontalRange.upperBound
        let topAnchor = verticalRange.lowerBound
        let bottomAnchor = verticalRange.upperBound

        let distanceToLeft = abs(next.x - leftAnchor)
        let distanceToRight = abs(next.x - rightAnchor)
        next.x = (distanceToLeft <= distanceToRight) ? leftAnchor : rightAnchor

        let distanceToTop = abs(next.y - topAnchor)
        let distanceToBottom = abs(next.y - bottomAnchor)
        next.y = (distanceToTop <= distanceToBottom) ? topAnchor : bottomAnchor

        hudPosition = next
        hudDragOffset = .zero
    }

    private func defaultHUDCenter(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        let horizontalRange = hudHorizontalRange(in: containerSize, safeAreaInsets: safeAreaInsets)
        let verticalRange = hudVerticalRange(in: containerSize.height, safeAreaInsets: safeAreaInsets)
        let target = CGPoint(x: horizontalRange.lowerBound, y: verticalRange.upperBound)
        return clampHUDPoint(target, in: containerSize, safeAreaInsets: safeAreaInsets)
    }

    private func clampHUDPoint(_ point: CGPoint, in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        let horizontalRange = hudHorizontalRange(in: containerSize, safeAreaInsets: safeAreaInsets)
        let verticalRange = hudVerticalRange(in: containerSize.height, safeAreaInsets: safeAreaInsets)
        return CGPoint(
            x: min(max(point.x, horizontalRange.lowerBound), horizontalRange.upperBound),
            y: min(max(point.y, verticalRange.lowerBound), verticalRange.upperBound)
        )
    }

    private func hudHorizontalRange(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> ClosedRange<CGFloat> {
        let effectiveWidth = hudCurrentWidth(in: containerSize, safeAreaInsets: safeAreaInsets)
        let halfWidth = effectiveWidth / 2
        let leadingInset = safeAreaInsets.leading + hudHorizontalLeadingPadding
        let trailingInset = safeAreaInsets.trailing + hudHorizontalTrailingPadding
        let containerWidth = max(containerSize.width, effectiveWidth)
        let minX = leadingInset + halfWidth
        let availableMaxX = containerWidth - (trailingInset + halfWidth)
        let maxX = max(availableMaxX, minX)
        return minX...maxX
    }

    private func hudCurrentWidth(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGFloat {
        if isMemoryExpanded {
            guard containerSize.width > 0 else { return hudExpandedWidthOrFallback }
            return hudExpandedDisplayWidth(in: containerSize, safeAreaInsets: safeAreaInsets)
        }
        return hudCompactWidthOrFallback
    }

    private func hudVerticalRange(in containerHeight: CGFloat, safeAreaInsets: EdgeInsets) -> ClosedRange<CGFloat> {
        let size = hudCurrentSize
        let top = safeAreaInsets.top + hudTopEdgePadding
        let bottom = safeAreaInsets.bottom + hudBottomEdgePadding
        let minY = (size.height / 2) + top
        let maxY = max(containerHeight - (size.height / 2 + bottom), minY)
        return minY...maxY
    }

    private var hudHorizontalLeadingPadding: CGFloat { 0 }

    private var hudHorizontalTrailingPadding: CGFloat { 0 }

    private var hudCompactWidthOrFallback: CGFloat {
        let width = hudCompactSize.width
        return width > 0 ? width : hudDefaultCompactSize.width
    }

    private var hudExpandedWidthOrFallback: CGFloat {
        let width = hudExpandedSize.width
        return width > 0 ? width : hudDefaultExpandedSize.width
    }

    private func hudExpandedDisplayWidth(in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGFloat {
        let horizontalPadding = hudHorizontalLeadingPadding + hudHorizontalTrailingPadding
        let constrainedWidth = containerSize.width - (safeAreaInsets.leading + safeAreaInsets.trailing + horizontalPadding)
        let safeAreaWidth = max(constrainedWidth, 0)
        guard safeAreaWidth > 0 else { return hudExpandedWidthOrFallback }
        if safeAreaWidth < hudExpandedMinimumWidth {
            return safeAreaWidth
        }
        return min(safeAreaWidth, hudExpandedWidthCeiling)
    }

    private var hudExpandedWidthCeiling: CGFloat { 360 }

    private var hudExpandedMinimumWidth: CGFloat { 220 }

    private var hudTopEdgePadding: CGFloat { 0 }

    private var hudBottomEdgePadding: CGFloat { isMemoryExpanded ? 3 : 2 }

    private var hudCurrentSize: CGSize {
        let size = isMemoryExpanded ? hudExpandedSize : hudCompactSize
        if size == .zero {
            return isMemoryExpanded ? hudDefaultExpandedSize : hudDefaultCompactSize
        }
        return size
    }

    private var hudDefaultCompactSize: CGSize { CGSize(width: 140, height: 50) }

    private var hudDefaultExpandedSize: CGSize { CGSize(width: 330, height: 220) }

    private func requestHUDResnap(with safeAreaInsets: EdgeInsets) {
        guard enableHUDResnapDuringLayout else { return }
        guard hudContainerSize != .zero else { return }
        let containerSize = hudContainerSize
        Task { @MainActor in
            withAnimation(hudSnapAnimation) {
                snapHUDPosition(in: containerSize, translation: .zero, safeAreaInsets: safeAreaInsets)
            }
        }
    }

    private struct MemoryHUDSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }

    private func mergeSafeAreaInsets(_ local: EdgeInsets, _ root: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: resolvedTopInset(localTop: local.top, rootTop: root.top),
            leading: resolvedHorizontalInset(local.leading, root.leading),
            bottom: max(local.bottom, root.bottom),
            trailing: resolvedHorizontalInset(local.trailing, root.trailing)
        )
    }

    private func resolvedTopInset(localTop: CGFloat, rootTop: CGFloat) -> CGFloat {
        let positiveLocal = localTop > 0 ? localTop : nil
        let positiveRoot = rootTop > 0 ? rootTop : nil
        if let local = positiveLocal, let root = positiveRoot {
            return min(local, root)
        }
        if let local = positiveLocal { return local }
        if let root = positiveRoot { return root }
        return 0
    }

    private func resolvedHorizontalInset(_ local: CGFloat, _ root: CGFloat) -> CGFloat {
        let positiveLocal = local > 0 ? local : nil
        let positiveRoot = root > 0 ? root : nil
        if let localValue = positiveLocal, let rootValue = positiveRoot {
            return min(localValue, rootValue)
        }
        if let localValue = positiveLocal { return localValue }
        if let rootValue = positiveRoot { return rootValue }
        return 0
    }

    private func ensureEnvironmentReadyForRun(tag: String) async -> BenchmarkEnvironment? {
        let desiredConfig = currentModelSelection
        guard !desiredConfig.isEmpty else {
            await MainActor.run {
                appendLog("\(tag) Aborted: Select at least one Core ML model in the Environment section.\n")
            }
            return nil
        }

        if env == nil || loadedConfiguration != desiredConfig {
            await prepareEnvironmentIfNeeded(force: true)
        }

        guard let env else {
            await MainActor.run {
                appendLog("\(tag) Failed: Benchmark environment unavailable.\n")
            }
            return nil
        }
        return env
    }

    @MainActor
    private func resetForNewRun() {
        log.removeAll()
        selectedOutputPage = 0
        outputCardResetToken &+= 1
    }

    private func runAll() async {
        let cases = orderedCases
        guard !cases.isEmpty, let env = await ensureEnvironmentReadyForRun(tag: "[RunAll]") else { return }
        await MainActor.run {
            resetForNewRun()
            isRunning = true
        }
        defer {
            Task { @MainActor in isRunning = false }
        }
        await MainActor.run { appendLog("\n[RunAll] Started at \(Date())\n") }
        await runSuite(env: env, cases: cases, includeSync: includeSyncBenchmarks)
        await MainActor.run { appendLog("[RunAll] Finished at \(Date())\n") }
    }

    private func runShort() async {
        let subset = Array(orderedCases.prefix(6))
        guard !subset.isEmpty, let env = await ensureEnvironmentReadyForRun(tag: "[RunShort]") else { return }
        await MainActor.run {
            resetForNewRun()
            isRunning = true
        }
        defer {
            Task { @MainActor in isRunning = false }
        }
        await MainActor.run { appendLog("\n[RunShort] Started at \(Date())\n") }
        await runSuite(env: env, cases: subset, includeSync: includeSyncBenchmarks)
        await MainActor.run { appendLog("[RunShort] Finished at \(Date())\n") }
    }

    private func runSuite(env: BenchmarkEnvironment, cases: [BenchmarkCase], includeSync: Bool) async {
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
            await runBenchmarksFor(groupTag: groupTag, kanaInput: kana, env: env, includeSync: includeSync)
        }
    }

    private var logEntries: [StructuredEntry] {
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
                let decoratedRows = decorateRows(rows, caseTag: headerParts.caseTag)
                entries.append(
                    StructuredEntry(
                        id: entryID,
                        icon: "list.number",
                        title: headerParts.title,
                        detail: headerParts.subtitle,
                        accent: .cyan,
                        category: .output,
                        rankingRows: decoratedRows
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
        logEntries.filter { $0.category == .status }
    }

    private var outputEntries: [StructuredEntry] {
        logEntries.filter { $0.category == .output }
    }

    private var benchmarkAverages: [BenchmarkAverage] {
        var stats: [String: (Double, Int)] = [:]
        for entry in logEntries {
            guard entry.category == .output, let rows = entry.rankingRows else { continue }
            for row in rows {
                guard let duration = row.durationValue else { continue }
                let key = row.variantKey.isEmpty ? row.label : row.variantKey
                var current = stats[key] ?? (0, 0)
                current.0 += duration
                current.1 += 1
                stats[key] = current
            }
        }
        return stats.map { key, value in
            BenchmarkAverage(variant: key, average: value.0 / Double(value.1), samples: value.1)
        }
        .sorted { $0.average < $1.average }
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
            rawDetail: rawDetail.isEmpty ? remainder : rawDetail,
            durationValue: durationValue,
            variantKey: label
        )
    }

    private func parseRankingHeader(from line: String) -> (title: String, subtitle: String, caseTag: String) {
        // Example: "===== Benchmark Ranking for [Case] (fast → slow) ====="
        guard let forRange = line.range(of: "for "), let suffixRange = line.range(of: "(fast") else {
            return ("Ranking Output", line, "")
        }
        let tagSegment = line[forRange.upperBound..<suffixRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let subtitleRange = line[suffixRange.lowerBound..<line.endIndex]
        let subtitle = subtitleRange
            .replacingOccurrences(of: "=====", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTag = tagSegment.replacingOccurrences(of: "](", with: "] (")
        return ("Ranking • \(cleanedTag)", subtitle.isEmpty ? "fast → slow" : subtitle, tagSegment)
    }

    private var orderedCases: [BenchmarkCase] {
        storedCases
    }

    private func encodedPrompt(from text: String) -> String {
        let trimmed = text.removingKanaMarkers().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\u{EE00}\(trimmed)\u{EE01}"
    }

    private var expectedOutputsByLabel: [String: String] {
        Dictionary(uniqueKeysWithValues: orderedCases.map { ($0.label, $0.expectedKanaOutput) })
    }

    private func decorateRows(_ rows: [RankingRow], caseTag: String) -> [RankingRow] {
        let rawTag = caseTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTag.isEmpty else { return rows }
        let expected = normalizedComparisonText(expectedOutputsByLabel[rawTag] ?? "")
        guard !expected.isEmpty else { return rows }
        return rows.map { row in
            let normalizedOutput = normalizedComparisonText(row.output)
            let match = !normalizedOutput.isEmpty &&
                (normalizedOutput.contains(expected) || expected.contains(normalizedOutput))
            let variantKey = variantKey(from: row.label, caseTag: rawTag)
            return RankingRow(
                position: row.position,
                label: row.label,
                duration: row.duration,
                input: row.input,
                output: row.output,
                rawDetail: row.rawDetail,
                statusSymbol: match ? "checkmark.seal.fill" : "xmark.seal.fill",
                statusColor: match ? .green : .pink,
                durationValue: row.durationValue,
                variantKey: variantKey
            )
        }
    }

    private func normalizedKanaText(_ text: String) -> String {
        text.removingKanaMarkers().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedComparisonText(_ text: String) -> String {
        let trimmed = normalizedKanaText(text)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func variantKey(from label: String, caseTag: String) -> String {
        guard !caseTag.isEmpty else { return label }
        return label.replacingOccurrences(of: caseTag, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func addCase(label: String, prompt: String, expected: String) {
        testCaseStore.addCase(label: label, prompt: prompt, expected: expected)
    }

    @MainActor
    private func updateCase(_ testCase: BenchmarkCase, label: String, prompt: String, expected: String) {
        testCaseStore.updateCase(testCase, label: label, prompt: prompt, expected: expected)
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
