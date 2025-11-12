//
//  ContentView.swift
//  swift-zenz-coreml-app
//
//  Created by Buseong Kim on 11/12/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var log: String = ""
    @State private var isRunning = false
    @State private var env: BenchmarkEnvironment? = nil
    @State private var verbose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core ML Benchmark Runner")
                .font(.title2).bold()

            Toggle("Verbose generation logs", isOn: $verbose)
                .onChange(of: verbose) { newValue in
                    GenerationLogConfig.enableVerbose = newValue
                }

            HStack {
                Button(action: { Task { await runAll() } }) {
                    Text(isRunning ? "Running…" : "Run All (23 cases)")
                }
                .disabled(isRunning || env == nil)

                Button(action: { Task { await runShort() } }) {
                    Text("Run Short Set")
                }
                .disabled(isRunning || env == nil)

                Button("Clear Log") { log.removeAll() }
            }

            ScrollView {
                LogTextView(text: log)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .border(Color.secondary)
            .frame(minHeight: 280)
        }
        .padding()
        .task {
            if env == nil {
                log.append("\n[Init] Loading model & tokenizer…\n")
                env = await makeBenchmarkEnvironment()
                log.append("[Init] Ready.\n")
            }
        }
    }

    private func runAll() async {
        guard let env else { return }
        isRunning = true
        defer { isRunning = false }
        log.append("\n[RunAll] Started at \(Date())\n")
        await runSuite(env: env, cases: allCases)
        log.append("[RunAll] Finished at \(Date())\n")
    }

    private func runShort() async {
        guard let env else { return }
        isRunning = true
        defer { isRunning = false }
        log.append("\n[RunShort] Started at \(Date())\n")
        await runSuite(env: env, cases: Array(allCases.prefix(6)))
        log.append("[RunShort] Finished at \(Date())\n")
    }

    private func runSuite(env: BenchmarkEnvironment, cases: [(String, String)]) async {
        // Register logger so benchmark output also appears in UI log
        setBenchmarkLogger { line in
            DispatchQueue.main.async {
                log.append(line + "\n")
            }
        }
        for (tag, kana) in cases {
            onLog?("[Case] \(tag)")
            await runBenchmarksFor(groupTag: tag, kanaInput: kana, env: env)
        }
    }

    // Same 23 inputs used in the XCTest, in the same order.
    private var allCases: [(String, String)] {
        [
            ("[ニホンゴ]", "\u{EE00}ニホンゴ\u{EE01}"),
            ("[カンコクゴ]", "\u{EE00}カンコクゴヲベンキョウスル\u{EE01}"),
            ("[LongJP]", "\u{EE00}ワタシハイマニホンゴノベンキョウヲシテイテ、スマートフォンノキーボードデヘンカンセイドヲアゲタイトオモッテイマス\u{EE01}"),
            ("[Greet1]", "\u{EE00}オハヨウゴザイマス\u{EE01}"),
            ("[Greet2]", "\u{EE00}ハジメマシテ、ワタシハスカイラインデス\u{EE01}"),
            ("[ShortQ]", "\u{EE00}ゲンキデスカ\u{EE01}"),
            ("[Weather]", "\u{EE00}キョウハトテモアツイデスネ\u{EE01}"),
            ("[Meetup]", "\u{EE00}アシタノゴゴサンジニエキデアイマショウ\u{EE01}"),
            ("[Dinner]", "\u{EE00}キョウノバンナニヲタベタイデスカ\u{EE01}"),
            ("[Culture]", "\u{EE00}ニホンノブンカニキョウミガアリマス\u{EE01}"),
            ("[KoreanSkill]", "\u{EE00}カンコクゴヲモットジョウズニハナセルヨウニナリタイデス\u{EE01}"),
            ("[HobbyMovie]", "\u{EE00}ヒマナトキハヨクエイガヲミマス\u{EE01}"),
            ("[HobbyBook]", "\u{EE00}ワタシノシュミハホンヲヨムコトデス\u{EE01}"),
            ("[PCFreeze]", "\u{EE00}コンピュータノガメンガフリーズシテシマイマシタ\u{EE01}"),
            ("[Battery]", "\u{EE00}スマホノバッテリーガスグニナクナッテコマッテイマス\u{EE01}"),
            ("[Keyboard]", "\u{EE00}キーボードノヘンカンセイドガアガルトモットハヤクウテマス\u{EE01}"),
            ("[Cafe]", "\u{EE00}キノウハトモダチトエキマエノカフェデコーヒーヲノミマシタ\u{EE01}"),
            ("[TimeMeet]", "\u{EE00}サンジニシゴトガオワルノデヨジニアエマス\u{EE01}"),
            ("[NextHoliday]", "\u{EE00}ツギノヤスミハドコニイキマショウカ\u{EE01}"),
            ("[LongJP2]", "\u{EE00}ワタシノシュミハホンヲヨムコトデ、トクニミステリーショウセツガスキデス\u{EE01}"),
            ("[LongJP3]", "\u{EE00}マイニチシゴトノマエニコーヒーヲイッパイノムノガナンタノシミデス\u{EE01}"),
            ("[LongJP4]", "\u{EE00}ワタシハマイニチネルトキニニジカンホドニホンゴノベンキョウヲシテイマス\u{EE01}"),
            ("[LongJPKeyboard]", "\u{EE00}イツモスマートフォンノキーボードデニホンゴヲウツノデ、ヘンカンセイドガタカイトホントウニタスカリマス\u{EE01}")
        ]
    }
}


struct LogTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false  // outer SwiftUI ScrollView handles scrolling
        textView.backgroundColor = .clear
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}
