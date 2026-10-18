import SwiftUI

struct WeeklyPage: View {
    @Environment(AppModel.self) private var model
    @State private var issues: [WeeklyIssue] = []
    @State private var selected = 0
    @State private var videos: [VideoItem] = []
    @State private var error = ""

    private var current: WeeklyIssue? { issues.first { $0.number == selected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !issues.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(issues.prefix(8)) { issue in
                                Button("\(issue.number)期") {
                                    guard issue.number != selected else { return }
                                    selected = issue.number
                                    Task { try? await loadVideos(issue.number) }
                                }
                                .font(.subheadline.weight(issue.number == selected ? .bold : .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(issue.number == selected ? .white : .primary)
                                .background {
                                    if issue.number == selected {
                                        Capsule().fill(Palette.bili.gradient)
                                    } else {
                                        Capsule().fill(Color.primary.opacity(0.06))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let current {
                    Text(current.name).font(.headline).lineLimit(2)
                    if !current.subject.isEmpty {
                        Text(current.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                if !error.isEmpty, videos.isEmpty {
                    ContentUnavailableView("没有这一期", systemImage: "flame", description: Text(error))
                }
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.title3.weight(.black).monospacedDigit())
                            .foregroundStyle(index < 3 ? Palette.bili : .secondary)
                            .frame(width: 28)
                        VideoCard(video: video, compact: true)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("每周必看")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let found = try await model.client.weeklyIssues()
            issues = found
            guard let first = found.first else {
                error = "没有每周必看"
                HotUIProof.record(["issue": 0, "name": "", "subject": "", "rows": 0, "covers": 0, "error": error])
                return
            }
            selected = first.number
            try await loadVideos(first.number, prove: true)
        } catch {
            self.error = error.localizedDescription
            HotUIProof.record(["issue": 0, "name": "", "subject": "", "rows": 0, "covers": 0, "error": self.error])
        }
    }

    private func loadVideos(_ number: Int, prove: Bool = false) async throws {
        let page = try await model.client.weeklyVideos(number: number)
        videos = page
        error = page.isEmpty ? "这一期没有视频" : ""
        await ImageStore.shared.prepare(urls: page.prefix(8).map(\.cover), maxPixel: 320)
        guard prove else { return }
        let issue = issues.first { $0.number == number }
        HotUIProof.record([
            "issue": number,
            "name": issue?.name ?? "",
            "subject": issue?.subject ?? "",
            "rows": page.count,
            "covers": ImageStore.preparedCount,
            "error": error
        ])
    }
}

struct PreciousPage: View {
    @Environment(AppModel.self) private var model
    @State private var videos: [VideoItem] = []
    @State private var headline = ""
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !headline.isEmpty {
                    Text(headline).font(.subheadline).foregroundStyle(.secondary)
                }
                if !error.isEmpty, videos.isEmpty {
                    ContentUnavailableView("没有入站必刷", systemImage: "star", description: Text(error))
                }
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.title3.weight(.black).monospacedDigit())
                            .foregroundStyle(index < 3 ? Palette.bili : .secondary)
                            .frame(width: 28)
                        VideoCard(video: video, compact: true)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("入站必刷")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await model.client.preciousVideos()
            videos = page.videos
            headline = page.explain
            error = page.videos.isEmpty ? "入站必刷是空的" : ""
            await ImageStore.shared.prepare(urls: page.videos.prefix(8).map(\.cover), maxPixel: 320)
            HotUIProof.record([
                "title": page.videos.first?.title ?? "",
                "explain": page.explain,
                "rows": page.videos.count,
                "covers": ImageStore.preparedCount,
                "error": error
            ])
        } catch {
            self.error = error.localizedDescription
            HotUIProof.record(["title": "", "explain": "", "rows": 0, "covers": 0, "error": self.error])
        }
    }
}
