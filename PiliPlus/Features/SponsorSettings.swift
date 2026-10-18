import SwiftUI

struct SponsorSettings: View {
    var body: some View {
        List {
            Section {
                Text("按视频号的哈希前缀，依次问 sponsor.ajay.app 和 bsbsb.top。命中的片段会标在进度条上。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("类别") {
                ForEach(SponsorCatalog.categories) { category in
                    Picker(selection: Binding(
                        get: { SponsorStore.action(for: category.id) },
                        set: { SponsorStore.set($0, for: category.id) }
                    )) {
                        ForEach(SponsorAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Circle().fill(category.color).frame(width: 8, height: 8)
                                Text(category.title)
                            }
                            Text(category.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("空降助手")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { SponsorSettingsProof.record() }
    }
}
