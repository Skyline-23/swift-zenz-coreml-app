import Foundation
import SwiftData

struct BenchmarkCaseSeed {
    let label: String
    let prompt: String

    static let defaults: [BenchmarkCaseSeed] = [
        .init(label: "[ニホンゴ]", prompt: "ニホンゴ"),
        .init(label: "[カンコクゴ]", prompt: "カンコクゴヲベンキョウスル"),
        .init(label: "[LongJP]", prompt: "ワタシハイマニホンゴノベンキョウヲシテイテ、スマートフォンノキーボードデヘンカンセイドヲアゲタイトオモッテイマス"),
        .init(label: "[Greet1]", prompt: "オハヨウゴザイマス"),
        .init(label: "[Greet2]", prompt: "ハジメマシテ、ワタシハスカイラインデス"),
        .init(label: "[ShortQ]", prompt: "ゲンキデスカ"),
        .init(label: "[Weather]", prompt: "キョウハトテモアツイデスネ"),
        .init(label: "[Meetup]", prompt: "アシタノゴゴサンジニエキデアイマショウ"),
        .init(label: "[Dinner]", prompt: "キョウノバンナニヲタベタイデスカ"),
        .init(label: "[Culture]", prompt: "ニホンノブンカニキョウミガアリマス"),
        .init(label: "[KoreanSkill]", prompt: "カンコクゴヲモットジョウズニハナセルヨウニナリタイデス"),
        .init(label: "[HobbyMovie]", prompt: "ヒマナトキハヨクエイガヲミマス"),
        .init(label: "[HobbyBook]", prompt: "ワタシノシュミハホンヲヨムコトデス"),
        .init(label: "[PCFreeze]", prompt: "コンピュータノガメンガフリーズシテシマイマシタ"),
        .init(label: "[Battery]", prompt: "スマホノバッテリーガスグニナクナッテコマッテイマス"),
        .init(label: "[Keyboard]", prompt: "キーボードノヘンカンセイドガアガルトモットハヤクウテマス"),
        .init(label: "[Cafe]", prompt: "キノウハトモダチトエキマエノカフェデコーヒーヲノミマシタ"),
        .init(label: "[TimeMeet]", prompt: "サンジニシゴトガオワルノデヨジニアエマス"),
        .init(label: "[NextHoliday]", prompt: "ツギノヤスミハドコニイキマショウカ"),
        .init(label: "[LongJP2]", prompt: "ワタシノシュミハホンヲヨムコトデ、トクニミステリーショウセツガスキデス"),
        .init(label: "[LongJP3]", prompt: "マイニチシゴトノマエニコーヒーヲイッパイノムノガナンタノシミデス"),
        .init(label: "[LongJP4]", prompt: "ワタシハマイニチネルトキニニジカンホドニホンゴノベンキョウヲシテイマス"),
        .init(label: "[LongJPKeyboard]", prompt: "イツモスマートフォンノキーボードデニホンゴヲウツノデ、ヘンカンセイドガタカイトホントウニタスカリマス")
    ]
}

@MainActor
struct TestCaseStore {
    private let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    func addCase(label: String, prompt: String) {
        let sanitized = sanitizedInputs(label: label, prompt: prompt)
        guard !sanitized.prompt.isEmpty else { return }
        let newCase = BenchmarkCase(label: sanitized.label, kanaPrompt: sanitized.prompt)
        context.insert(newCase)
        try? context.save()
    }

    func updateCase(_ testCase: BenchmarkCase, label: String, prompt: String) {
        let sanitized = sanitizedInputs(label: label, prompt: prompt)
        guard !sanitized.prompt.isEmpty else { return }
        testCase.label = sanitized.label.isEmpty ? testCase.label : sanitized.label
        testCase.kanaPrompt = sanitized.prompt
        try? context.save()
    }

    func deleteCase(_ testCase: BenchmarkCase) {
        context.delete(testCase)
        try? context.save()
    }

    func resetToDefault(using existingCases: [BenchmarkCase]) {
        existingCases.forEach { context.delete($0) }
        seedDefaultCases()
        try? context.save()
    }

    func ensureDefaultsIfNeeded(currentCount: Int) {
        guard currentCount == 0 else { return }
        seedDefaultCases()
        try? context.save()
    }

    private func seedDefaultCases() {
        for seed in BenchmarkCaseSeed.defaults {
            let newCase = BenchmarkCase(label: seed.label, kanaPrompt: seed.prompt)
            context.insert(newCase)
        }
    }

    private func sanitizedInputs(label: String, prompt: String) -> (label: String, prompt: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedLabel = trimmedLabel.isEmpty ? "[Custom]" : trimmedLabel
        let sanitizedPrompt = prompt
            .removingKanaMarkers()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (sanitizedLabel, sanitizedPrompt)
    }
}
