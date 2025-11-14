import SwiftUI

struct StructuredEntry: Identifiable {
    enum Category {
        case status
        case output
    }

    let id: String
    let icon: String
    let title: String
    let detail: String
    let accent: Color
    let category: Category
    let rankingRows: [RankingRow]?
}

struct RankingRow: Identifiable {
    let id = UUID()
    let position: Int
    let label: String
    let duration: String
    let input: String
    let output: String
    let rawDetail: String
    let statusSymbol: String?
    let statusColor: Color?
    let durationValue: Double?
    let variantKey: String

    init(
        position: Int,
        label: String,
        duration: String,
        input: String,
        output: String,
        rawDetail: String,
        statusSymbol: String? = nil,
        statusColor: Color? = nil,
        durationValue: Double? = nil,
        variantKey: String = ""
    ) {
        self.position = position
        self.label = label
        self.duration = duration
        self.input = input
        self.output = output
        self.rawDetail = rawDetail
        self.statusSymbol = statusSymbol
        self.statusColor = statusColor
        self.durationValue = durationValue
        self.variantKey = variantKey
    }
}

struct StatusCardView: View {
    let entry: StructuredEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.title3)
                .foregroundStyle(entry.accent)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Text(entry.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .liquidGlassTile(
            tint: entry.accent,
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

struct StatusPlaceholderView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Start a benchmark to see live status updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 34)
        .liquidGlassTile(
            tint: .secondary,
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

struct EntryCardView: View {
    let entry: StructuredEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: entry.icon)
                    .font(.title3)
                    .foregroundStyle(entry.accent)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer()
            }
            if let rows = entry.rankingRows, !rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("\(row.position)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        if let symbol = row.statusSymbol {
                                            Image(systemName: symbol)
                                                .font(.caption)
                                                .foregroundStyle(row.statusColor ?? .secondary)
                                        }
                                        Text(row.label)
                                            .font(.caption.weight(.semibold))
                                    }
                                    if row.input.isEmpty, row.output.isEmpty, row.duration.isEmpty {
                                        Text(row.rawDetail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if !row.duration.isEmpty {
                                    Text("\(row.duration) s")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            } else {
                Text(entry.detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct OutputPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Output cards will appear here as results stream in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private extension RankingRow {
    var promptSnippet: String {
        input.removingKanaMarkers().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var outputSnippet: String {
        let trimmedOutput = output.removingKanaMarkers().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return "" }
        let trimmedPrompt = promptSnippet
        if !trimmedPrompt.isEmpty, trimmedOutput.hasPrefix(trimmedPrompt) {
            let remainder = trimmedOutput.dropFirst(trimmedPrompt.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.isEmpty ? trimmedOutput : String(remainder)
        }
        return trimmedOutput
    }
}

private extension String {
    func truncated(to length: Int) -> String {
        guard count > length, length > 1 else { return self }
        let end = index(startIndex, offsetBy: length - 1)
        return String(self[...end]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
