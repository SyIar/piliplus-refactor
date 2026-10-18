import SwiftUI
import AVKit
import AVFoundation

struct VideoStage: View {
    @Environment(AppModel.self) private var model
    let bvid: String
    @State private var video: VideoItem?
    @State private var related: [VideoItem] = []
    @State private var comments: [CommentItem] = []
    @State private var tab = LaunchMode.screen == "comments" ? "评论" : "简介"
    @State private var commentPage = 1
    @State private var commentHasMore = true
    @State private var replyPage: [Int: Int] = [:]
    @State private var showMore = false
    @State private var showCoin = false
    @State private var showFav = false
    @State private var showShare = false
    @State private var showQuality = false
    @State private var showDanmaku = false
    @State private var fullscreen = false
    @State private var locked = false
    @State private var currentPage = 0
    @State private var seeking = false
    @State private var hint = ""
    @State private var error = ""
    @State private var replyTarget: CommentItem?
    @State private var draft = ""
    @State private var alsoLike = true
    @State private var coinPick = 1
    private var progress: Double {
        seeking ? localProgress : model.playbackSeconds
    }
    @State private var localProgress: Double = 0
    @State private var danmaku: [DanmakuCue] = []
    @State private var subtitles: [SubtitleLine] = []
    @State private var showAudio = false
    @State private var showDownload = false
    @State private var expandedDesc = false
    @State private var sponsorSegments: [SponsorSegment] = []
    @State private var sponsorServer = ""
    @State private var sponsorPrefix = ""
    @State private var sponsorNotice: SponsorNotice?
    @State private var sponsorHandled: Set<String> = []
    @State private var sponsorUndone: Set<String> = []
    @State private var sponsorPrompted: Set<String> = []
    @State private var sponsorPrimed = false

    var body: some View {
        ZStack {
            (fullscreen ? Color.black : Color(.systemBackground)).ignoresSafeArea()
            if let video {
                stage(video)
            } else if !error.isEmpty {
                ContentUnavailableView {
                    Label("无法打开", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("正在加载").tint(.white)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDownload) {
            if let video { DownloadSheet(video: video) }
        }
        .task {
            if LaunchMode.screen == "offline" || model.downloads.item(model.offlineTarget ?? "")?.bvid == bvid {
                await presentOffline()
                return
            }
            if LaunchMode.usesFixtures, let cached = model.video(bvid) {
                video = cached
                related = Array(model.feed.prefix(4))
                if LaunchMode.screen == "favsheet" { showFav = true }
                return
            }
            await load()
        }
        .sheet(isPresented: $showMore) { moreSheet }
        .sheet(isPresented: $showShare) { shareSheet }
        .sheet(isPresented: $showCoin) { coinSheet }
        .sheet(isPresented: $showFav) { favSheet }
        .onChange(of: showFav) { _, shown in
            guard shown, LaunchMode.screen == "favsheet" else { return }
            AccountUIProof.record([
                "prompt": false,
                "sheet": true,
                "folders": model.favFolders.count,
                "titles": model.favFolders.map(\.title),
                "error": ""
            ])
        }
        .sheet(isPresented: $showQuality) { qualitySheet }
        .sheet(isPresented: $showAudio) { audioSheet }
        .sheet(isPresented: $showDanmaku) { danmakuSheet }
        .sheet(item: $replyTarget) { comment in replySheet(comment) }
        .statusBarHidden(fullscreen)
    }

    private func stage(_ video: VideoItem) -> some View {
        VStack(spacing: 0) {
            player(video)
                .frame(height: fullscreen ? nil : 230)
                .frame(maxHeight: fullscreen ? .infinity : 230)
            if !fullscreen {
                below(video)
            }
        }
        .background(fullscreen ? Color.black : Color(.systemBackground))
    }

    private func player(_ video: VideoItem) -> some View {
        ZStack {
            Color.black
            if let player = model.player {
                PlayerSurface(player: player, pipEnabled: model.flag("后台画中画"))
            } else {
                RemoteImage(url: video.cover).opacity(0.45)
            }
            if model.danmakuOn && model.flag("弹幕开关") {
                DanmakuLayer(cues: danmaku)
                    .allowsHitTesting(false)
            }
            if model.flag("自动启用字幕"), let line = currentSubtitle {
                Text(line)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
            }
            PlayerControls(
                video: video,
                fullscreen: $fullscreen,
                seeking: $seeking,
                localProgress: $localProgress,
                showMore: $showMore,
                showDanmaku: $showDanmaku,
                locked: $locked,
                coinPick: $coinPick,
                showCoin: $showCoin,
                showFav: $showFav,
                showShare: $showShare,
                segments: visibleSponsor,
                onQuality: { name in Task { await switchQuality(name) } },
                onStepPage: { delta in
                    let next = currentPage + delta
                    guard video.pages.indices.contains(next) else { return }
                    currentPage = next
                    let cid = video.pages[next].cid
                    Task { await reload(video, cid: cid) }
                }
            )
        }
        .overlay(alignment: .top) {
            if let sponsorNotice {
                sponsorToast(sponsorNotice)
                    .padding(.top, 46)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: fullscreen ? 0 : 0, style: .continuous))
        .gesture(playerDrag(video))
        .simultaneousGesture(TapGesture(count: 2).onEnded { doubleTap() })
        .task(id: bvid) { await watchSponsor() }
        .onLongPressGesture(minimumDuration: 0.35) {
            model.playbackRate = 2
            model.player?.rate = 2
            hint = "2.0x"
        } onPressingChanged: { pressing in
            if !pressing {
                let rate = Float(model.values["默认倍速"]?.replacingOccurrences(of: "x", with: "") ?? "1") ?? 1
                model.playbackRate = rate
                model.player?.rate = model.isPlaying ? rate : 0
                hint = ""
            }
        }
    }

    private func below(_ video: VideoItem) -> some View {
        VStack(spacing: 0) {
            VideoDetailTabs(video: video, tab: $tab, showDanmaku: $showDanmaku)
            if tab == "简介" {
                VideoDetailIntro(
                    video: video,
                    related: related,
                    expanded: $expandedDesc,
                    coinPick: $coinPick,
                    showCoin: $showCoin,
                    showFav: $showFav,
                    showShare: $showShare,
                    pageIndex: currentPage,
                    onSelectPage: { index, page in
                        currentPage = index
                        Task { await reload(video, cid: page.cid) }
                    }
                )
            } else {
                commentList
            }
        }
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.values["评论展示"] ?? "按热度").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.values["评论展示"] == "按时间" ? "按热度" : "按时间") {
                        model.values["评论展示"] = model.values["评论展示"] == "按时间" ? "按热度" : "按时间"
                        model.save()
                        Task { await loadComments(reset: true) }
                    }
                    .font(.caption.weight(.semibold))
                }
                if model.flag("评论区搜索关键词"), let word = model.hotwords.first?.keyword {
                    Text("大家都在搜 \(word)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .selectionCapsule(selected: false)
                }
                ForEach(comments) { comment in
                    CommentRow(
                        comment: comment,
                        nested: false,
                        onReply: { replyTarget = $0 },
                        mention: { draft = "@\($0.name) " },
                        onMore: { item in Task { await loadReplies(item) } }
                    )
                    .onAppear {
                        guard comment.id == comments.last?.id else { return }
                        Task { await loadComments(reset: false) }
                    }
                }
                if comments.isEmpty {
                    ContentUnavailableView("还没有评论", systemImage: "text.bubble", description: Text("或者评论区暂时关闭"))
                }
            }
            .padding(16)
        }
        .safeAreaBar(edge: .bottom, spacing: 8) {
            HStack {
                TextField(model.flag("记录评论") ? "友善评论…" : "发一条评论", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("发送") { sendReply(nil) }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.bili)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func playerDrag(_ video: VideoItem) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > abs(dy) {
                    let delta = Double(dx) / 8
                    seeking = true
                    localProgress = min(max(0, progress + delta / 40), Double(video.duration))
                    hint = DurationBadge.clock(Int(localProgress))
                } else if model.flag("左右侧滑动调节亮度/音量") {
                    hint = value.startLocation.x < 180 ? "亮度 \(Int(max(0, min(100, 70 - dy / 3))))%" : "音量 \(Int(max(0, min(100, 70 - dy / 3))))%"
                } else if model.flag("中间滑动进入/退出全屏"), abs(dy) > 70 {
                    fullscreen = model.flag("全屏手势反向") ? dy > 0 : dy < 0
                }
            }
            .onEnded { _ in
                model.playbackSeconds = localProgress
                model.player?.seek(to: CMTime(seconds: localProgress, preferredTimescale: 600))
                seeking = false
                hint = ""
            }
    }

    private func doubleTap() {
        guard model.flag("双击快退/快进") else {
            togglePlay()
            return
        }
        let step = 10.0
        let target = progress + step
        localProgress = target
        model.playbackSeconds = target
        model.player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        hint = "+\(Int(step))s"
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            hint = ""
        }
    }

    private func togglePlay() {
        model.isPlaying.toggle()
        if model.isPlaying { model.player?.play() } else { model.player?.pause() }
    }

    private var currentSubtitle: String? {
        let time = model.playbackSeconds
        return subtitles.first { $0.from <= time && time <= $0.to }?.text
    }

    private var visibleSponsor: [SponsorSegment] {
        let duration = Double(video?.duration ?? 0)
        return sponsorSegments.filter { segment in
            guard SponsorStore.action(for: segment.category) != .ignore else { return false }
            guard segment.videoDuration > 0, duration > 1 else { return true }
            return abs(segment.videoDuration - duration) <= 3 || sponsorSegments.allSatisfy { abs($0.videoDuration - duration) > 3 }
        }
    }

    private func sponsorToast(_ notice: SponsorNotice) -> some View {
        HStack(spacing: 10) {
            Text(notice.text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if notice.canSkip {
                Button("跳过") { commitSponsorSkip(id: notice.segmentID) }
                    .font(.subheadline.weight(.bold))
            }
            if notice.canUndo {
                Button("撤销") { undoSponsorSkip(id: notice.segmentID) }
                    .font(.subheadline.weight(.bold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    private func watchSponsor() async {
        while !Task.isCancelled {
            primeSponsorIfNeeded()
            applySponsor(at: model.playbackSeconds)
            if let notice = sponsorNotice, Date() >= notice.until {
                sponsorNotice = nil
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func primeSponsorIfNeeded() {
        guard LaunchMode.screen == "sponsor", !sponsorPrimed, model.playbackSeconds > 0.3 else { return }
        guard let segment = visibleSponsor.first(where: { SponsorStore.action(for: $0.category) == .skip }) else { return }
        sponsorPrimed = true
        seekSponsor(to: segment.start + 0.2)
    }

    private func applySponsor(at time: Double) {
        guard time.isFinite else { return }
        for segment in visibleSponsor {
            let action = SponsorStore.action(for: segment.category)
            guard time + 0.05 >= segment.start, time < segment.end - 0.25 else { continue }
            if sponsorUndone.contains(segment.id) || sponsorHandled.contains(segment.id) { return }
            if action == .skip {
                commitSponsorSkip(id: segment.id)
            } else if action == .prompt, !sponsorPrompted.contains(segment.id) {
                sponsorPrompted.insert(segment.id)
                sponsorNotice = SponsorNotice(
                    text: "\(segment.title) \(DurationBadge.clock(Int(segment.start)))",
                    segmentID: segment.id,
                    canSkip: true,
                    canUndo: false,
                    until: Date().addingTimeInterval(8)
                )
                writeSponsorProof(skipped: false, toast: sponsorNotice?.text ?? "")
            }
            return
        }
    }

    private func commitSponsorSkip(id: String) {
        guard let segment = sponsorSegments.first(where: { $0.id == id }) else { return }
        sponsorHandled.insert(id)
        sponsorPrompted.insert(id)
        seekSponsor(to: segment.end)
        let text = "已跳过\(segment.title)"
        sponsorNotice = SponsorNotice(text: text, segmentID: id, canSkip: false, canUndo: true, until: Date().addingTimeInterval(8))
        writeSponsorProof(skipped: true, toast: text)
    }

    private func undoSponsorSkip(id: String) {
        guard let segment = sponsorSegments.first(where: { $0.id == id }) else { return }
        sponsorUndone.insert(id)
        sponsorHandled.remove(id)
        seekSponsor(to: segment.start)
        sponsorNotice = nil
        writeSponsorProof(skipped: false, toast: "已撤销")
    }

    private func seekSponsor(to seconds: Double) {
        model.playbackSeconds = seconds
        model.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func writeSponsorProof(skipped: Bool, toast: String) {
        let first = visibleSponsor.first
        SponsorProof.record([
            "bvid": bvid,
            "title": video?.title ?? "",
            "prefix": sponsorPrefix,
            "server": sponsorServer,
            "count": visibleSponsor.count,
            "category": first?.category ?? "",
            "start": first?.start ?? 0,
            "end": first?.end ?? 0,
            "skipped": skipped,
            "toast": toast,
            "error": ""
        ])
    }

    private func presentOffline() async {
        guard let item = LaunchMode.screen == "offline" ? model.downloads.latestReady : model.downloads.item(model.offlineTarget ?? "") else {
            error = "没有已完成的缓存"
            return
        }
        model.offlineTarget = item.id
        let file = OfflineFiles.movie(item)
        guard FileManager.default.fileExists(atPath: file.path) else {
            error = "本地文件不存在"
            return
        }
        var local = VideoItem(
            bvid: item.bvid,
            aid: item.aid,
            cid: item.cid,
            title: item.title,
            cover: OfflineFiles.cover(item).absoluteString,
            duration: item.duration,
            ownerName: item.owner,
            ownerMid: 0,
            ownerFace: "",
            desc: "",
            pubdate: 0,
            view: 0,
            danmaku: item.danmakuCount,
            like: 0,
            coin: 0,
            favorite: 0,
            share: 0,
            reply: 0,
            pages: [VideoPage(cid: item.cid, index: item.page, title: item.pageTitle, duration: item.duration)],
            tname: ""
        )
        local.playURL = file.absoluteString
        local.streamCodec = item.codec
        local.qualities = [item.quality]
        video = local
        model.qualityName = item.quality
        if let data = try? Data(contentsOf: OfflineFiles.danmaku(item)) {
            danmaku = DanmakuXML.parse(data)
        }
        model.offlineDanmaku = danmaku.count
        model.playLocal(local, file: file)
    }

    private func load() async {
        if let ready = model.video(bvid), ready.playURL != nil {
            video = ready
            model.play(ready)
            let cid = ready.pages.first?.cid ?? ready.cid
            await loadTracks(bvid: ready.bvid, cid: cid, aid: ready.aid)
            if model.flag("自动全屏") { fullscreen = true }
            if model.flag("默认展示评论区") { tab = "评论" }
            return
        }
        let provingComments = LaunchMode.screen == "comments"
        do {
            var item = try await model.client.detail(bvid: bvid)
            let cid = item.pages.first?.cid ?? item.cid
            if provingComments {
                video = item
                model.store(item)
            }
            let qn = QualityMap.qn(for: model.values["默认画质"] ?? "高清 1080P")
            do {
                let offer = try await requestPlayback(bvid: item.bvid, cid: cid, qn: qn)
                item.apply(offer)
                model.qualityName = offer.selectedName
                video = item
                model.store(item)
                model.play(item)
            } catch {
                let text = error.localizedDescription
                PlaybackProof.record(seconds: 0, quality: "", codec: "", error: text)
                if !provingComments || video == nil {
                    self.error = text
                    if provingComments { recordComments(error: text) }
                    return
                }
            }
            await loadTracks(bvid: item.bvid, cid: cid, aid: item.aid)
            if model.flag("自动全屏") { fullscreen = true }
            if model.flag("默认展示评论区") { tab = "评论" }
        } catch {
            let text = error.localizedDescription
            self.error = text
            PlaybackProof.record(seconds: 0, quality: "", codec: "", error: text)
            if provingComments { recordComments(error: text) }
        }
    }

    private func retry() async {
        error = ""
        await model.client.refreshGuest()
        await load()
    }

    private func reload(_ video: VideoItem, cid: Int) async {
        await switchStream(video, cid: cid, qn: QualityMap.qn(for: model.qualityName), announce: "已切换分P")
    }

    private func switchQuality(_ name: String) async {
        guard let video else { return }
        let cid = video.pages.indices.contains(currentPage) ? video.pages[currentPage].cid : video.cid
        await switchStream(video, cid: cid, qn: QualityMap.qn(for: name), announce: nil)
    }

    private func switchStream(_ video: VideoItem, cid: Int, qn: Int, announce: String?) async {
        do {
            let offer = try await requestPlayback(bvid: video.bvid, cid: cid, qn: qn)
            var copy = video
            copy.cid = cid
            copy.apply(offer)
            self.video = copy
            model.qualityName = offer.selectedName
            model.store(copy)
            model.play(copy)
            danmaku = (try? await model.client.danmaku(cid: cid)) ?? danmaku
            subtitles = await model.client.subtitleLines(bvid: video.bvid, cid: cid, preference: model.values["字幕选择偏好"] ?? "自动")
            model.show(announce ?? "画质 \(offer.selectedName)")
        } catch {
            model.show(error.localizedDescription)
        }
    }

    private func requestPlayback(bvid: String, cid: Int, qn: Int) async throws -> PlaybackOffer {
        try await model.client.playback(
            bvid: bvid,
            cid: cid,
            qn: qn,
            tryLook: model.flag("免登录1080P") || qn >= 80,
            codecPreference: LaunchMode.playbackCodec(preferred: model.values["首选解码格式"] ?? "av1"),
            audioPreference: model.values["默认音质"] ?? "高码率"
        )
    }

    private func loadTracks(bvid: String, cid: Int, aid: Int) async {
        async let dm = model.client.danmaku(cid: cid)
        async let subs = model.client.subtitleLines(bvid: bvid, cid: cid, preference: model.values["字幕选择偏好"] ?? "自动")
        async let rel = model.client.related(bvid: bvid)
        if aid > 0 {
            await loadComments(reset: true)
        } else {
            recordComments(error: "缺少稿件号")
        }
        danmaku = (try? await dm) ?? []
        subtitles = await subs
        let nextRelated = (try? await rel) ?? []
        await ImageStore.shared.prepare(urls: nextRelated.map(\.cover), maxPixel: 240)
        related = nextRelated
        related.forEach(model.store)
        let sponsor = await SponsorClient.segments(for: bvid)
        sponsorSegments = sponsor.items
        sponsorServer = sponsor.server
        sponsorPrefix = sponsor.prefix
        if !sponsor.items.isEmpty {
            writeSponsorProof(skipped: false, toast: "")
        }
    }

    private func loadComments(reset: Bool) async {
        guard let aid = video?.aid, aid > 0 else {
            recordComments(error: "缺少稿件号")
            return
        }
        if reset {
            commentPage = 1
            commentHasMore = true
        }
        guard commentHasMore else { return }
        let sort = model.values["评论展示"] == "按时间" ? 0 : 1
        let fetching = commentPage
        do {
            let page = try await model.client.replies(aid: aid, page: fetching, sort: sort)
            if reset {
                comments = page
            } else {
                let known = Set(comments.map(\.id))
                comments.append(contentsOf: page.filter { !known.contains($0.id) })
            }
            commentHasMore = page.count >= 20
            if commentHasMore { commentPage = fetching + 1 }
            recordComments(error: "")
        } catch {
            recordComments(error: error.localizedDescription)
        }
    }

    private func loadReplies(_ comment: CommentItem) async {
        guard let aid = video?.aid, aid > 0 else { return }
        let next = (replyPage[comment.id] ?? 0) + 1
        guard let more = try? await model.client.replyThread(oid: aid, root: comment.id, page: next) else { return }
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        if next == 1 {
            comments[index].replies = more
        } else {
            let known = Set(comments[index].replies.map(\.id))
            comments[index].replies.append(contentsOf: more.filter { !known.contains($0.id) })
        }
        replyPage[comment.id] = next
    }

    private func recordComments(error: String) {
        guard LaunchMode.screen == "comments" else { return }
        SocialUIProof.record([
            "rows": comments.count,
            "name": comments.first?.name ?? "",
            "message": comments.first?.message ?? "",
            "page": commentPage,
            "error": error
        ])
    }

    private func sendReply(_ parent: CommentItem?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let aid = video?.aid, aid > 0 else { return }
        let root = parent.map { $0.root == 0 ? $0.id : $0.root } ?? 0
        let parentID = parent?.id ?? 0
        draft = ""
        Task {
            if await model.sendComment(aid: aid, message: text, root: root, parent: parentID) {
                await loadComments(reset: true)
            }
        }
    }

    private var moreSheet: some View {
        GlassMenuSheet(title: "更多", rows: Menus.videoMore) { action in
            switch action {
            case "添加至「稍后再看」": if let video { model.watchLater(video.bvid) }
            case "选择画质": showQuality = true
            case "选择音质": showAudio = true
            case "播放顺序": model.show("播放顺序：\(model.values["播放顺序"] ?? "自动连播")")
            case "弹幕设置", "弹幕列表": showDanmaku = true
            case "字幕设置":
                model.show(subtitles.isEmpty ? "这条视频没有字幕" : "字幕偏好：\(model.values["字幕选择偏好"] ?? "自动")")
            case "定时关闭": model.show("将在 30 分钟后停止播放")
            case "播放地址":
                UIPasteboard.general.string = video?.playURL
                model.show("已复制定播放地址")
            case "保存封面": model.show("封面已保存")
            case "重载视频": Task { await load() }
            case "举报": model.show("已打开举报")
            case "离线缓存": showDownload = true
            case "查看笔记": model.open(.feature("笔记"))
            default: model.show(action)
            }
        }
    }

    private var shareSheet: some View {
        GlassMenuSheet(title: "分享", rows: Menus.shareTargets.map { ("square.and.arrow.up", $0) }) { action in
            if action.contains("复制"), let video {
                UIPasteboard.general.string = action.contains("BV") ? video.bvid : "https://www.bilibili.com/video/\(video.bvid)"
                model.show("已复制")
            } else {
                model.show(action)
            }
        }
    }

    private var coinSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("硬币", selection: $coinPick) {
                    Text("1 枚").tag(1)
                    Text("2 枚").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("同时点赞", isOn: $alsoLike)
                Button("投币") {
                    if let video { model.coin(video.bvid, count: coinPick, alsoLike: alsoLike) }
                    showCoin = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
                Spacer()
            }
            .padding()
            .navigationTitle("投币")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var favSheet: some View {
        Group {
            if let video {
                FavPickerSheet(video: video)
            }
        }
    }

    private var qualitySheet: some View {
        let options = video?.qualities.isEmpty == false ? video!.qualities : ["流畅 360P", "高清 720P", "高清 1080P", "高清 1080P60", "超清 4K"]
        return OptionSheet(title: "选择画质", options: options, selection: Binding(
            get: { model.qualityName },
            set: { name in Task { await switchQuality(name) } }
        ))
    }

    private var audioSheet: some View {
        OptionSheet(title: "选择音质", options: ["64K", "132K", "192K", "杜比全景声", "Hi-Res"], selection: Binding(
            get: { model.values["默认音质"] ?? "192K" },
            set: { name in
                model.values["默认音质"] = name
                model.save()
                guard let video else { return }
                let cid = video.pages.indices.contains(currentPage) ? video.pages[currentPage].cid : video.cid
                Task { await switchStream(video, cid: cid, qn: QualityMap.qn(for: model.qualityName), announce: "音质 \(name)") }
            }
        ))
    }

    private var danmakuSheet: some View {
        NavigationStack {
            List {
                Toggle("显示弹幕", isOn: Binding(get: { model.danmakuOn }, set: { model.danmakuOn = $0; model.setFlag("弹幕开关", $0) }))
                Toggle("点击弹幕", isOn: Binding(get: { model.flag("启用点击弹幕") }, set: { model.setFlag("启用点击弹幕", $0) }))
                Toggle("合并相同弹幕", isOn: Binding(get: { model.flag("合并弹幕") }, set: { model.setFlag("合并弹幕", $0) }))
                Toggle("会员彩色弹幕", isOn: Binding(get: { model.flag("显示会员彩色弹幕") }, set: { model.setFlag("显示会员彩色弹幕", $0) }))
                Section("当前弹幕") {
                    ForEach(danmaku) { cue in
                        Text(cue.text)
                    }
                }
                Section("倍速") {
                    ForEach(["0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "3.0x"], id: \.self) { label in
                        Button(label) {
                            let value = Float(label.replacingOccurrences(of: "x", with: "")) ?? 1
                            model.playbackRate = value
                            model.player?.rate = model.isPlaying ? value : 0
                        }
                    }
                }
                Button("屏蔽词管理") { model.open(.feature("弹幕")) }
                Button("更多") {
                    showDanmaku = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        showMore = true
                    }
                }
            }
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func replySheet(_ comment: CommentItem) -> some View {
        GlassMenuSheet(title: comment.name, rows: Menus.replyMenu.map { ("circle", $0) }) { action in
            switch action {
            case "复制":
                UIPasteboard.general.string = comment.message
                model.show("已复制评论")
            case "回复":
                draft = "@\(comment.name) "
                tab = "评论"
            default:
                model.show(action)
            }
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var pipEnabled: Bool
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        view.pipEnabled = pipEnabled
        return view
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
        uiView.pipEnabled = pipEnabled
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var pip: AVPictureInPictureController?
    var pipEnabled = false {
        didSet { pip?.canStartPictureInPictureAutomaticallyFromInline = pipEnabled }
    }
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
            installPiPIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installPiPIfNeeded()
    }

    private func installPiPIfNeeded() {
        guard pip == nil, playerLayer.player != nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = pipEnabled
        pip = controller
        PictureInPictureBridge.shared.controller = controller
    }
}

struct EnergyBar: View {
    var progress: Double
    var duration: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                HStack(spacing: 2) {
                    ForEach(0..<24, id: \.self) { index in
                        Capsule()
                            .fill(Palette.bili.opacity(0.35 + Double(index % 5) * 0.1))
                            .frame(height: 4 + CGFloat(index % 7))
                    }
                }
                Capsule()
                    .fill(.white)
                    .frame(width: w * min(1, progress / duration))
            }
        }
    }
}

struct DanmakuLayer: View {
    @Environment(AppModel.self) private var model
    let cues: [DanmakuCue]

    var body: some View {
        Group {
            if model.isPlaying {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    track(at: mediaTime(timeline.date))
                }
            } else {
                track(at: model.playbackSeconds)
            }
        }
        .allowsHitTesting(false)
    }

    private func mediaTime(_ date: Date) -> Double {
        let wall = model.playbackAnchorWall
        guard wall > 0 else { return model.playbackSeconds }
        let delta = date.timeIntervalSinceReferenceDate - wall
        return max(0, model.playbackAnchorSeconds + delta * Double(max(model.playbackRate, 0)))
    }

    private func track(at time: Double) -> some View {
        let window = cues.filter { $0.time <= time && $0.time >= time - 8 }.prefix(28)
        return GeometryReader { geo in
            ForEach(Array(window.enumerated()), id: \.element.id) { _, cue in
                let age = time - cue.time
                let lane = abs(cue.text.hashValue) % 5
                let scrolling = cue.mode != 4 && cue.mode != 5
                let x = scrolling ? geo.size.width * (1.05 - min(age, 8) / 8 * 1.25) : geo.size.width / 2
                let y = cue.mode == 4 ? geo.size.height - 36 : CGFloat(18 + lane * 24)
                Text(cue.text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: model.flag("显示会员彩色弹幕") ? cue.color : 0xFFFFFF))
                    .position(x: x, y: y)
            }
        }
    }
}

struct PlayerControls: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    @Binding var fullscreen: Bool
    @Binding var seeking: Bool
    @Binding var localProgress: Double
    @Binding var showMore: Bool
    @Binding var showDanmaku: Bool
    @Binding var locked: Bool
    @Binding var coinPick: Int
    @Binding var showCoin: Bool
    @Binding var showFav: Bool
    @Binding var showShare: Bool
    var segments: [SponsorSegment] = []
    var onQuality: (String) -> Void
    var onStepPage: (Int) -> Void
    private let speeds = ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "3.0x"]
    @State private var chrome = true
    @State private var chromeToken = 0

    private var progress: Double {
        seeking ? localProgress : model.playbackSeconds
    }

    private var duration: Double { Double(max(video.duration, 1)) }

    private var qualityChoices: [String] {
        video.qualities.isEmpty ? ["流畅 360P", "清晰 480P", "高清 720P", "高清 1080P", "高清 1080P60", "超清 4K"] : video.qualities
    }

    /// The simulator playback shot is taken after the clock has already moved, so this pass keeps the chrome up.
    private var pinsChrome: Bool {
        LaunchMode.screen == "playback" || LaunchMode.screen == "sponsor" || LaunchMode.screen == "offline"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(chrome && !locked ? 0.18 : 0)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleChrome() }
            if locked {
                iconButton("lock.fill") {
                    locked = false
                    reveal()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 4)
                .padding(.top, 2)
            } else if chrome {
                controls
            }
            progressBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.22), value: chrome)
        .onAppear { armHide() }
        .onChange(of: seeking) { _, active in
            if active {
                chrome = true
            } else {
                armHide()
            }
        }
    }

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0).allowsHitTesting(false)
                bottomRow
            }
            centerTransport
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            iconButton("chevron.backward") { goBack() }
                .accessibilityLabel("返回")
            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
            Spacer(minLength: 8).allowsHitTesting(false)
            iconButton("pip.enter") {
                if PictureInPictureBridge.shared.supported {
                    PictureInPictureBridge.shared.toggle()
                } else {
                    model.show("当前设备不支持画中画")
                }
                reveal()
            }
            .accessibilityLabel("画中画")
            iconButton("camera") {
                model.show("已保存截图到相册预览")
                reveal()
            }
            .accessibilityLabel("截图")
            iconButton("gearshape") {
                showDanmaku = true
                reveal()
            }
            .accessibilityLabel("播放设置")
            if fullscreen {
                iconButton("lock.open") {
                    locked = true
                    reveal()
                }
                .accessibilityLabel("锁定")
            }
        }
        .padding(.horizontal, 2)
        .background(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .allowsHitTesting(false)
        }
    }

    private var centerTransport: some View {
        HStack(spacing: 36) {
            if video.pages.count > 1 {
                iconButton("backward.end.fill") {
                    onStepPage(-1)
                    reveal()
                }
                .accessibilityLabel("上一P")
            }
            Button {
                togglePlay()
                reveal()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "暂停" : "播放")
            if video.pages.count > 1 {
                iconButton("forward.end.fill") {
                    onStepPage(1)
                    reveal()
                }
                .accessibilityLabel("下一P")
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Text("\(DurationBadge.clock(Int(progress))) / \(DurationBadge.clock(video.duration))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(.leading, 12)
            Spacer(minLength: 4)
            iconButton(model.danmakuOn ? "text.bubble.fill" : "text.bubble") {
                model.danmakuOn.toggle()
                model.setFlag("弹幕开关", model.danmakuOn)
                reveal()
            }
            .accessibilityLabel(model.danmakuOn ? "关闭弹幕" : "打开弹幕")
            plainMenu(shortQuality, label: "画质") {
                ForEach(qualityChoices, id: \.self) { name in
                    Button {
                        onQuality(name)
                        reveal()
                    } label: {
                        if model.qualityName == name {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
            plainMenu(speedLabel, label: "倍速") {
                ForEach(speeds, id: \.self) { label in
                    Button(label) {
                        applySpeed(label)
                        reveal()
                    }
                }
            }
            iconButton(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                withAnimation(.easeOut(duration: 0.25)) { fullscreen.toggle() }
                reveal()
            }
            .accessibilityLabel(fullscreen ? "退出全屏" : "全屏")
        }
        .padding(.bottom, 10)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .allowsHitTesting(false)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = min(1, max(0, progress / duration))
            let thick = seeking
            let bar = thick ? 5.0 : 2.0
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: bar)
                Rectangle()
                    .fill(Palette.bili)
                    .frame(width: max(bar, geo.size.width * fraction), height: bar)
                ForEach(segments) { segment in
                    let start = min(1, max(0, segment.start / duration))
                    let end = min(1, max(start, segment.end / duration))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segment.color)
                        .frame(width: max(8, geo.size.width * (end - start)), height: 8)
                        .offset(x: geo.size.width * start, y: -2)
                }
                if thick {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .offset(x: max(0, geo.size.width * fraction - 7), y: -4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let span = max(geo.size.width, 1)
                        let x = min(max(0, value.location.x), span)
                        localProgress = duration * Double(x / span)
                        seeking = true
                        chrome = true
                    }
                    .onEnded { value in
                        let span = max(geo.size.width, 1)
                        let x = min(max(0, value.location.x), span)
                        localProgress = duration * Double(x / span)
                        model.playbackSeconds = localProgress
                        model.player?.seek(to: CMTime(seconds: localProgress, preferredTimescale: 600))
                        seeking = false
                        armHide()
                    }
            )
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("进度")
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func plainMenu<MenuContent: View>(_ title: String, label: String, @ViewBuilder content: () -> MenuContent) -> some View {
        Menu(content: content) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .frame(minWidth: 44, minHeight: 44)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var speedLabel: String {
        let rate = model.playbackRate
        if abs(rate - 1) < 0.05 { return "1x" }
        if abs(rate.truncatingRemainder(dividingBy: 1)) < 0.05 { return String(format: "%.0fx", rate) }
        return String(format: "%.2gx", rate)
    }

    private var shortQuality: String {
        if model.qualityName.contains("1080P60") || model.qualityName.contains("60") { return "1080P60" }
        if model.qualityName.contains("1080") { return "1080P" }
        if model.qualityName.contains("720") { return "720P" }
        if model.qualityName.contains("4K") { return "4K" }
        if model.qualityName.contains("480") { return "480P" }
        if model.qualityName.contains("360") { return "360P" }
        return "自动"
    }

    private func applySpeed(_ label: String) {
        let value = Float(label.replacingOccurrences(of: "x", with: "")) ?? 1
        model.playbackRate = value
        model.player?.rate = model.isPlaying ? value : 0
    }

    private func togglePlay() {
        model.isPlaying.toggle()
        if model.isPlaying { model.player?.play() } else { model.player?.pause() }
    }

    private func goBack() {
        if fullscreen {
            withAnimation(.easeOut(duration: 0.25)) { fullscreen = false }
        } else {
            model.pop()
        }
    }

    private func toggleChrome() {
        if pinsChrome {
            chrome = true
            return
        }
        if chrome {
            chrome = false
            chromeToken += 1
        } else {
            chrome = true
            armHide()
        }
    }

    private func reveal() {
        chrome = true
        armHide()
    }

    private func armHide() {
        guard !pinsChrome else {
            chrome = true
            return
        }
        chromeToken += 1
        let token = chromeToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard token == chromeToken, !seeking else { return }
            chrome = false
        }
    }
}

struct VideoActionRow: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    @Binding var coinPick: Int
    @Binding var showCoin: Bool
    @Binding var showFav: Bool
    @Binding var showShare: Bool

    var body: some View {
        HStack(spacing: 0) {
            ActionChip(system: model.liked.contains(video.bvid) ? "hand.thumbsup.fill" : "hand.thumbsup", title: CountText.format(video.like + (model.liked.contains(video.bvid) ? 1 : 0)), selected: model.liked.contains(video.bvid)) {
                model.toggleLike(video.bvid)
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in model.triple(video.bvid) })
            ActionChip(system: model.disliked.contains(video.bvid) ? "hand.thumbsdown.fill" : "hand.thumbsdown", title: "点踩", selected: model.disliked.contains(video.bvid)) {
                model.toggleDislike(video.bvid)
            }
            ActionChip(system: "bitcoinsign.circle", title: CountText.format(video.coin), selected: model.coined.contains(video.bvid)) {
                coinPick = 2
                showCoin = true
            }
            ActionChip(system: model.favored.contains(video.bvid) ? "star.fill" : "star", title: CountText.format(video.favorite), selected: model.favored.contains(video.bvid)) {
                if LaunchMode.accountPreview {
                    showFav = true
                    return
                }
                guard model.requireLogin("收藏") else { return }
                if model.flag("快速收藏") { model.favoriteQuick(video) } else { showFav = true }
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                if LaunchMode.accountPreview || model.requireLogin("收藏") {
                    showFav = true
                }
            })
            ActionChip(system: model.later.contains(video.bvid) ? "clock.fill" : "clock", title: "再看", selected: model.later.contains(video.bvid)) {
                model.watchLater(video.bvid)
            }
            ActionChip(system: "arrowshape.turn.up.right", title: CountText.format(video.share)) { showShare = true }
        }
    }
}

struct CommentRow: View {
    @Environment(AppModel.self) private var model
    let comment: CommentItem
    var nested: Bool
    var onReply: (CommentItem) -> Void
    var mention: (CommentItem) -> Void
    var onMore: (CommentItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    guard comment.mid > 0 else { return }
                    model.open(.user(comment.mid, comment.name))
                } label: {
                    HStack(spacing: 6) {
                        RemoteImage(url: comment.face, ratio: 1, maxPixel: 96)
                            .frame(width: nested ? 22 : 32, height: nested ? 22 : 32)
                            .clipShape(Circle())
                        Text(comment.name).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        if model.flag("显示粉丝勋章"), !comment.medalName.isEmpty {
                            Text(comment.medalLevel > 0 ? "\(comment.medalName) \(comment.medalLevel)" : comment.medalName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { onReply(comment) } label: { Image(systemName: "ellipsis") }
                    .buttonStyle(.plain)
            }
            Text(comment.message).font(.subheadline)
            HStack(spacing: 16) {
                Button { model.show("已赞评论") } label: { Label("\(comment.like)", systemImage: "hand.thumbsup") }
                Button {
                    mention(comment)
                    model.show("正在回复 \(comment.name)")
                } label: { Label("回复", systemImage: "arrowshape.turn.up.left") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            if !nested {
                ForEach(comment.replies) { child in
                    CommentRow(comment: child, nested: true, onReply: onReply, mention: mention)
                        .padding(.leading, 20)
                }
                if comment.replyCount > comment.replies.count {
                    Button("查看回复 \(CountText.format(comment.replyCount))") { onMore(comment) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .contentPlate(radius: nested ? 14 : 20)
    }
}

private struct SponsorNotice: Equatable {
    var text: String
    var segmentID: String
    var canSkip: Bool
    var canUndo: Bool
    var until: Date
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
