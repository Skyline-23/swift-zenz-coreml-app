import Foundation
import SwiftData

struct BenchmarkCaseSeed {
    let label: String
    let prompt: String
    let expected: String

    init(label: String, prompt: String, expected: String) {
        self.label = label
        self.prompt = prompt
        self.expected = expected
    }

    static let defaults: [BenchmarkCaseSeed] = [
        .init(label: "[ニホンゴ]", prompt: "ニホンゴ", expected: "日本語"),
        .init(label: "[カンコクゴ]", prompt: "カンコクゴヲベンキョウスル", expected: "韓国語を勉強する"),
        .init(label: "[LongJP]", prompt: "ワタシハイマニホンゴノベンキョウヲシテイテ、スマートフォンノキーボードデヘンカンセイドヲアゲタイトオモッテイマス", expected: "私は今日本語の勉強をしていて、スマートフォンのキーボードで変換精度を上げたいと思っています"),
        .init(label: "[Greet1]", prompt: "オハヨウゴザイマス", expected: "おはようございます"),
        .init(label: "[Greet2]", prompt: "ハジメマシテ、ワタシハスカイラインデス", expected: "初めまして、私はスカイラインです"),
        .init(label: "[ShortQ]", prompt: "ゲンキデスカ", expected: "元気ですか"),
        .init(label: "[Weather]", prompt: "キョウハトテモアツイデスネ", expected: "今日はとても暑いですね"),
        .init(label: "[Meetup]", prompt: "アシタノゴゴサンジニエキデアイマショウ", expected: "明日の午後3時に駅で会いましょう"),
        .init(label: "[Dinner]", prompt: "キョウノバンハナニヲタベタイデスカ", expected: "今日の晩は何を食べたいですか"),
        .init(label: "[Culture]", prompt: "ニホンノブンカニキョウミガアリマス", expected: "日本の文化に興味があります"),
        .init(label: "[KoreanSkill]", prompt: "カンコクゴヲモットジョウズニハナセルヨウニナリタイデス", expected: "韓国語をもっと上手に話せるようになりたいです"),
        .init(label: "[HobbyMovie]", prompt: "ヒマナトキハヨクエイガヲミマス", expected: "暇な時はよく映画を観ます"),
        .init(label: "[HobbyBook]", prompt: "ワタシノシュミハホンヲヨムコトデス", expected: "私の趣味は本を読むことです"),
        .init(label: "[PCFreeze]", prompt: "コンピュータノガメンガフリーズシテシマイマシタ", expected: "コンピュータの画面がフリーズしてしまいました"),
        .init(label: "[Battery]", prompt: "スマホノバッテリーガスグニナクナッテコマッテイマス", expected: "スマホのバッテリーがすぐになくなって困っています"),
        .init(label: "[Keyboard]", prompt: "キーボードノヘンカンセイドガアガルトモットハヤクウテマス", expected: "キーボードの変換精度が上がるともっと早く打てます"),
        .init(label: "[Cafe]", prompt: "キノウハトモダチトエキマエノカフェデコーヒーヲノミマシタ", expected: "昨日は友達と駅前のカフェでコーヒーを飲みました"),
        .init(label: "[TimeMeet]", prompt: "サンジニシゴトガオワルノデヨジニアエマス", expected: "3時に仕事が終わるので4時に会えます"),
        .init(label: "[NextHoliday]", prompt: "ツギノヤスミハドコニイキマショウカ", expected: "次の休みはどこに行きましょうか"),
        .init(label: "[LongJP2]", prompt: "ワタシノシュミハホンヲヨムコトデ、トクニミステリーショウセツガスキデス", expected: "私の趣味は本を読むことで、特にミステリー小説が好きです"),
        .init(label: "[LongJP3]", prompt: "マイニチシゴトノマエニコーヒーヲイッパイノムノガナニヨリノタノシミデス", expected: "毎日仕事の前にコーヒーをいっぱい飲むのが何よりの楽しみです"),
        .init(label: "[LongJP4]", prompt: "ワタシハマイニチネルマエニニジカンホドニホンゴノベンキョウヲシテイマス", expected: "私は毎日寝る前に二時間ほど日本語を勉強しています"),
        .init(label: "[LongJPKeyboard]", prompt: "イツモスマートフォンノキーボードデニホンゴヲウツノデ、ヘンカンセイドガタカイトホントウニタスカリマス", expected: "いつもスマートフォンのキーボードで日本語を打つので、変換精度が高いと本当に助かります")
    ]
}

@MainActor
struct TestCaseStore {
    private let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    func addCase(label: String, prompt: String, expected: String) {
        guard let sanitized = sanitizedInputs(label: label, prompt: prompt, expected: expected),
              !sanitized.prompt.isEmpty
        else { return }
        let newCase = BenchmarkCase(
            label: sanitized.label,
            kanaPrompt: sanitized.prompt,
            expectedKanaOutput: sanitized.expected
        )
        context.insert(newCase)
        try? context.save()
    }

    func updateCase(_ testCase: BenchmarkCase, label: String, prompt: String, expected: String) {
        guard let sanitized = sanitizedInputs(label: label, prompt: prompt, expected: expected),
              !sanitized.prompt.isEmpty
        else { return }
        testCase.label = sanitized.label.isEmpty ? testCase.label : sanitized.label
        testCase.kanaPrompt = sanitized.prompt
        testCase.expectedKanaOutput = sanitized.expected
        try? context.save()
    }

    func deleteCase(_ testCase: BenchmarkCase) {
        context.delete(testCase)
        try? context.save()
    }

    func resetToDefault(using existingCases: [BenchmarkCase]) {
        existingCases.forEach { context.delete($0) }
        do {
            try seedDefaultCases()
            try context.save()
        } catch {
            print("[TestCaseStore] Failed to reset defaults: \(error)")
        }
    }

    func ensureDefaultsIfNeeded(currentCount: Int) {
        guard currentCount == 0 else { return }
        let descriptor = FetchDescriptor<BenchmarkCase>()
        let persistedCount = (try? context.fetchCount(descriptor)) ?? 0
        guard persistedCount == 0 else { return }
        do {
            try seedDefaultCases()
            try context.save()
        } catch {
            print("[TestCaseStore] Failed to seed defaults: \(error)")
        }
    }

    private func seedDefaultCases() throws {
        try ensureStoreDirectoryExists()
        for seed in BenchmarkCaseSeed.defaults {
            let newCase = BenchmarkCase(
                label: seed.label,
                kanaPrompt: seed.prompt,
                expectedKanaOutput: seed.expected
            )
            context.insert(newCase)
        }
    }

    private func ensureStoreDirectoryExists() throws {
        let fm = FileManager.default
        guard let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        if !fm.fileExists(atPath: appSupportURL.path) {
            try fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
    }

    private func sanitizedInputs(label: String, prompt: String, expected: String) -> (label: String, prompt: String, expected: String)? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedLabel = trimmedLabel.isEmpty ? "[Custom]" : trimmedLabel
        let sanitizedPrompt = prompt
            .removingKanaMarkers()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedExpected = expected
            .removingKanaMarkers()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedExpected.isEmpty else { return nil }
        return (sanitizedLabel, sanitizedPrompt, sanitizedExpected)
    }
}
