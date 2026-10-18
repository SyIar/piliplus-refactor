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
    @State private var chapters: [ChapterMark] = []
    @State private var energy: [Double] = []
    @State private var shot: VideoShotPage?
    @State private var shotSheets: [Int: UIImage] = [:]
    @State private var scrubPreview: UIImage?
    @State private var danmakuDraft = ""
    @State private var resumeApplied = 0.0
    @State private var resumeSource = ""
    @State private var autoplayFrom = ""
    @State private var autoplayTo = ""
    @State private var autoplayReason = ""
    @State private var autoplayArmed = false
    @State private var autoplaySawZero = false
    @State private var didContinue = false

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
        .onAppear {
            model.videoPageVisible = true
            if LaunchMode.screen == "sleep" { showDanmaku = true }
        }
        .onDisappear { model.videoPageVisible = false }
        .onChange(of: showDanmaku) { _, shown in
            guard shown, LaunchMode.screen == "sleep" else { return }
            PlaybackUIProof.record("sleep", [
                "sheet": true,
                "options": PlaybackSleep.options,
                "loginGuide": !model.loggedIn,
                "error": ""
            ])
        }
        .onChange(of: model.playbackSeconds) { _, seconds in
            noteExtraProofs(seconds)
        }
        .onChange(of: model.playbackEndedToken) { _, token in
            guard token > 0, autoplayEnabled else { return }
            Task { await continueAfterEnd() }
        }
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
                chapters: chapters,
                energy: energy,
                scrubPreview: scrubPreview,
                onScrub: { seconds in Task { await updateScrubPreview(at: seconds) } },
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
                    autoplayNote: autoplayCaption,
                    onSelectPage: { index, page in
                        currentPage = index
                        Task { await reload(video, cid: page.cid) }
                    },
                    onSelectEpisode: { episode in
                        Task { await playEpisode(episode) }
                    }
                )
            } else {
                commentList
            }
        }
    }

    private func offlineFile(_ video: VideoItem) -> Bool {
        video.playURL?.hasPrefix("file:") == true
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
        let movie = OfflineFiles.movie(item)
        let videoFile = OfflineFiles.video(item)
        let audioFile = OfflineFiles.audio(item)
        let file = FileManager.default.fileExists(atPath: movie.path) ? movie : videoFile
        let audio = file == movie ? nil : (FileManager.default.fileExists(atPath: audioFile.path) ? audioFile : nil)
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
            pubdate: item.pubdate ?? 0,
            view: item.viewCount ?? 0,
            danmaku: item.danmakuCount,
            like: item.likeCount ?? 0,
            coin: item.coinCount ?? 0,
            favorite: item.favoriteCount ?? 0,
            share: item.shareCount ?? 0,
            reply: item.replyCount ?? 0,
            pages: [VideoPage(cid: item.cid, index: item.page, title: item.pageTitle, duration: item.duration)],
            tname: ""
        )
        local.playURL = file.absoluteString
        local.audioURL = audio?.absoluteString
        local.streamCodec = item.codec
        local.qualities = [item.quality]
        video = local
        model.qualityName = item.quality
        if let data = try? Data(contentsOf: OfflineFiles.danmaku(item)) {
            danmaku = DanmakuXML.parse(data)
        }
        model.offlineDanmaku = danmaku.count
        model.playLocal(local, file: file, audio: audio)
    }

    private func load() async {
        if let ready = model.video(bvid), ready.playURL != nil {
            video = ready
            let cid = ready.pages.first?.cid ?? ready.cid
            adoptExtras(bvid: ready.bvid, cid: cid, duration: ready.duration)
            playFresh(ready, cid: cid)
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
                adoptExtras(bvid: item.bvid, cid: cid, duration: item.duration)
                playFresh(item, cid: cid)
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
        guard let video, !offlineFile(video) else { return }
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
        let covers = ImageStore.preparedCount
        related = nextRelated
        related.forEach(model.store)
        if let video {
            DetailProof.record(
                title: video.title,
                owner: video.ownerName,
                collection: video.collectionTitle.isEmpty ? model.seasonTitle : video.collectionTitle,
                related: related.count,
                covers: covers
            )
        }
        await loadDecorations(bvid: bvid, cid: cid)
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
            case "选择画质":
                if let video, offlineFile(video) {
                    model.show("离线画质 \(model.qualityName)")
                } else {
                    showQuality = true
                }
            case "选择音质": showAudio = true
            case "播放顺序": showDanmaku = true
            case "弹幕设置", "弹幕列表": showDanmaku = true
            case "字幕设置":
                model.show(subtitles.isEmpty ? "这条视频没有字幕" : "字幕偏好：\(model.values["字幕选择偏好"] ?? "自动")")
            case "定时关闭": showDanmaku = true
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
                Section("定时关闭") {
                    Picker("定时关闭", selection: Binding(
                        get: { model.sleepChoice },
                        set: { model.chooseSleep($0) }
                    )) {
                        ForEach(PlaybackSleep.options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("发送弹幕") {
                    if model.loggedIn, let video {
                        TextField("发一条弹幕", text: $danmakuDraft)
                        Button("发送") {
                            let text = danmakuDraft
                            danmakuDraft = ""
                            Task { await model.sendDanmaku(video, message: text) }
                        }
                        .disabled(danmakuDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("登录后发送弹幕") { model.open(.login) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Section("播放顺序") {
                    Picker("播放顺序", selection: Binding(
                        get: { model.values["播放顺序"] ?? "自动连播" },
                        set: { model.values["播放顺序"] = $0; model.save() }
                    )) {
                        ForEach(["自动连播", "单集循环", "列表循环", "播完暂停", "倒序播放"], id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
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
        .presentationDetents(LaunchMode.screen == "sleep" ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(LaunchMode.screen == "sleep" ? .disabled : .enabled(upThrough: .medium))
    }

    private var autoplayCaption: String {
        guard LaunchMode.screen == "autoplay", !autoplayReason.isEmpty else { return "" }
        return autoplayReason == "page" ? "已自动播放下一P" : "已自动播放相关视频"
    }

    private var autoplayEnabled: Bool {
        switch LaunchMode.screen {
        case nil, "autoplay", "bangumi-play": return true
        default: return false
        }
    }

    private func playFresh(_ item: VideoItem, cid: Int) {
        let start = initialStart(item, cid: cid)
        if LaunchMode.screen == "resume" {
            resumeApplied = start
            let local = PlaybackMemory.position(cid: cid)
            let remote = Double(max(item.progress, 0))
            resumeSource = remote > local && remote > 0 ? "server" : "local"
        }
        if LaunchMode.screen == "autoplay", autoplayFrom.isEmpty {
            autoplayFrom = "\(item.bvid)#\(cid)"
        }
        model.play(item, at: start)
        if LaunchMode.screen == "autoplay" { armAutoplay(item) }
    }

    private func initialStart(_ item: VideoItem, cid: Int) -> Double {
        switch LaunchMode.screen {
        case "playback", "sponsor", "offline", "autoplay", "chapters", "scrub", "sleep", "comments", "favsheet":
            return 0
        default:
            let duration = item.pages.first { $0.cid == cid }?.duration ?? item.duration
            return model.resumePosition(cid: cid, duration: duration, server: item.progress)
        }
    }

    private func adoptExtras(bvid: String, cid: Int, duration: Int) {
        guard model.extrasKey == "\(bvid)#\(cid)" else { return }
        chapters = model.chapterMarks
        energy = model.energySamples
        shot = model.preparedShot
        if let preview = model.preparedPreview { scrubPreview = preview }
        if LaunchMode.screen == "scrub", scrubPreview != nil {
            localProgress = Double(max(duration, 1)) * 0.35
            seeking = true
            PlaybackUIProof.record("scrub", [
                "images": shot?.images.count ?? 0,
                "frames": shot?.index.count ?? 0,
                "showing": true,
                "error": ""
            ])
        }
        recordChapters()
    }

    private func loadDecorations(bvid: String, cid: Int) async {
        let key = "\(bvid)#\(cid)"
        if model.extrasKey == key {
            recordChapters()
            return
        }
        async let marksTask = model.client.playerChapters(bvid: bvid, cid: cid)
        async let barsTask = model.client.energyBars(cid: cid)
        let page = await model.client.videoShot(bvid: bvid, cid: cid)
        chapters = await marksTask
        energy = await barsTask
        if energy.count < 8 {
            let density = PlaybackMarkup.danmakuEnergy(danmaku)
            if density.count >= 8 { energy = density }
        }
        shot = page
        model.chapterMarks = chapters
        model.energySamples = energy
        model.preparedShot = page
        model.extrasKey = key
        recordChapters()
        if LaunchMode.screen == "scrub" {
            await finishScrub(duration: video?.duration ?? 0)
        }
    }

    private func updateScrubPreview(at seconds: Double) async {
        guard let page = shot else { return }
        let cell = PlaybackMarkup.frameIndex(at: seconds, index: page.index)
        let per = max(1, page.columns * page.rows)
        let sheetIndex = cell / per
        guard page.images.indices.contains(sheetIndex) else { return }
        let sheetImage: UIImage
        if let cached = shotSheets[sheetIndex] {
            sheetImage = cached
        } else if let fetched = await model.client.fetchImage(page.images[sheetIndex]) {
            shotSheets[sheetIndex] = fetched
            sheetImage = fetched
        } else {
            return
        }
        scrubPreview = PlaybackMarkup.crop(sheet: sheetImage, columns: page.columns, rows: page.rows, cell: cell)
    }

    private func finishScrub(duration: Int) async {
        guard let page = shot else {
            PlaybackUIProof.record("scrub", ["images": 0, "frames": 0, "showing": false, "error": "没有找到预览图"])
            return
        }
        let seconds = Double(max(duration, 1)) * 0.35
        let cell = PlaybackMarkup.frameIndex(at: seconds, index: page.index)
        let per = max(1, page.columns * page.rows)
        let sheetIndex = cell / per
        guard page.images.indices.contains(sheetIndex),
              let image = await model.client.fetchImage(page.images[sheetIndex]),
              let piece = PlaybackMarkup.crop(sheet: image, columns: page.columns, rows: page.rows, cell: cell) else {
            PlaybackUIProof.record("scrub", [
                "images": page.images.count,
                "frames": page.index.count,
                "showing": false,
                "error": "预览图没有裁出来"
            ])
            return
        }
        scrubPreview = piece
        localProgress = seconds
        seeking = true
        PlaybackUIProof.record("scrub", [
            "images": page.images.count,
            "frames": page.index.count,
            "showing": true,
            "error": ""
        ])
    }

    private func recordChapters() {
        guard LaunchMode.screen == "chapters" else { return }
        guard chapters.count >= 1, energy.count >= 8, let title = chapters.first?.title, !title.isEmpty else { return }
        PlaybackUIProof.record("chapters", [
            "chapters": chapters.count,
            "energy": energy.count,
            "title": title,
            "error": ""
        ])
    }

    private func noteExtraProofs(_ seconds: Double) {
        if LaunchMode.screen == "resume", resumeApplied >= 8, abs(seconds - resumeApplied) < 8 {
            PlaybackUIProof.record("resume", [
                "applied": resumeApplied,
                "seconds": seconds,
                "source": resumeSource,
                "bvid": video?.bvid ?? "",
                "error": ""
            ])
        }
        if LaunchMode.screen == "bangumi-play", model.seasonEpisodes.count >= 2, seconds >= 0.8 {
            let episode = model.seasonEpisodes.first { $0.bvid == bvid }?.label ?? ""
            PlaybackUIProof.record("bangumi-play", [
                "count": model.seasonEpisodes.count,
                "episode": episode,
                "seconds": seconds,
                "title": model.seasonTitle,
                "error": episode.isEmpty ? "剧集标题是空的" : ""
            ])
        }
        if LaunchMode.screen == "autoplay", !autoplayTo.isEmpty, autoplayTo != autoplayFrom {
            let current = "\(model.nowPlaying?.bvid ?? "")#\(model.nowPlaying?.cid ?? 0)"
            guard current == autoplayTo else { return }
            if seconds < 0.3 { autoplaySawZero = true }
            if autoplaySawZero, seconds >= 0.4, seconds <= 5 {
                PlaybackUIProof.record("autoplay", [
                    "from": autoplayFrom,
                    "to": autoplayTo,
                    "reason": autoplayReason,
                    "seconds": seconds,
                    "error": ""
                ])
            }
        }
    }

    private func armAutoplay(_ item: VideoItem) {
        guard !autoplayArmed else { return }
        autoplayArmed = true
        Task { await primeAutoplay(item) }
    }

    private func primeAutoplay(_ item: VideoItem) async {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            let readyTime = model.playbackSeconds > 0.4
            let readyNext = item.pages.count > 1 || !related.isEmpty
            if readyTime && readyNext { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let duration = Double(max(item.duration, 1))
        let token = model.playbackEndedToken
        if duration > 8, let player = model.player {
            let target = max(0.5, duration - 1.2)
            await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        try? await Task.sleep(for: .seconds(3.2))
        guard model.playbackEndedToken == token else { return }
        await continueAfterEnd()
    }

    private func continueAfterEnd() async {
        guard autoplayEnabled, !didContinue, let video else { return }
        didContinue = true
        if model.sleepChoice == "播完当前" {
            model.player?.pause()
            model.isPlaying = false
            model.show("已定时关闭")
            didContinue = false
            return
        }
        let order = model.values["播放顺序"] ?? "自动连播"
        switch order {
        case "播完暂停":
            model.player?.pause()
            model.isPlaying = false
        case "单集循环":
            model.play(video, at: 0)
        case "倒序播放":
            await playNeighbor(video, delta: -1)
        default:
            await playNeighbor(video, delta: 1)
        }
        didContinue = false
    }

    private func playNeighbor(_ video: VideoItem, delta: Int) async {
        let nextIndex = currentPage + delta
        if video.pages.indices.contains(nextIndex) {
            currentPage = nextIndex
            let page = video.pages[nextIndex]
            autoplayReason = "page"
            autoplaySawZero = false
            autoplayTo = "\(video.bvid)#\(page.cid)"
            await reload(video, cid: page.cid)
            return
        }
        let pool = delta < 0 ? related.reversed() : related
        guard let next = pool.first(where: { $0.bvid != video.bvid }) else {
            model.player?.pause()
            model.isPlaying = false
            model.show("没有下一个视频")
            return
        }
        await playRelated(next)
    }

    private func playRelated(_ item: VideoItem) async {
        do {
            var detail = try await model.client.detail(bvid: item.bvid)
            let cid = detail.pages.first?.cid ?? detail.cid
            let offer = try await requestPlayback(bvid: detail.bvid, cid: cid, qn: QualityMap.qn(for: model.qualityName))
            detail.apply(offer)
            autoplayReason = "related"
            autoplaySawZero = false
            autoplayTo = "\(detail.bvid)#\(cid)"
            video = detail
            currentPage = 0
            model.qualityName = offer.selectedName
            model.store(detail)
            model.play(detail, at: 0)
            await loadTracks(bvid: detail.bvid, cid: cid, aid: detail.aid)
        } catch {
            model.show(error.localizedDescription)
        }
    }

    private func playEpisode(_ episode: EpisodeItem) async {
        guard !episode.bvid.isEmpty else { return }
        if episode.bvid == bvid, let video {
            if let index = video.pages.firstIndex(where: { $0.cid == episode.cid }) {
                currentPage = index
            }
            await reload(video, cid: episode.cid)
            return
        }
        await model.playListedEpisode(episode)
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
    var chapters: [ChapterMark] = []
    var energy: [Double] = []
    var scrubPreview: UIImage?
    var onScrub: (Double) -> Void = { _ in }
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
        switch LaunchMode.screen {
        case "playback", "sponsor", "offline", "resume", "autoplay", "bangumi-play", "chapters", "scrub", "sleep", "detail", "detail-dark":
            return true
        default:
            return false
        }
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
            scrubOverlay
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
            if offlineFile {
                Text(shortQuality)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("画质 \(model.qualityName)")
            } else {
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

    private var scrubOverlay: some View {
        GeometryReader { geo in
            let fraction = min(1, max(0, progress / duration))
            ZStack(alignment: .bottomLeading) {
                if seeking, let scrubPreview {
                    Image(uiImage: scrubPreview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                        .position(
                            x: min(max(68, geo.size.width * fraction), max(68, geo.size.width - 68)),
                            y: geo.size.height - 86
                        )
                }
                if let title = activeChapter, !title.isEmpty {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.leading, 8)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var activeChapter: String? {
        guard model.flag("显示视频分段信息"), !chapters.isEmpty else { return nil }
        let time = Int(progress)
        return chapters.last(where: { chapterSeconds($0) <= Double(time) })?.title ?? chapters.first?.title
    }

    private func chapterSeconds(_ mark: ChapterMark) -> Double {
        if duration > 0, Double(mark.from) > duration * 2, mark.from > 1000 {
            return Double(mark.from) / 1000
        }
        return Double(mark.from)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = min(1, max(0, progress / duration))
            let thick = seeking
            let bar = thick ? 5.0 : 2.0
            let showEnergy = model.flag("显示高能进度条") && energy.count >= 4
            ZStack(alignment: .bottomLeading) {
                if showEnergy {
                    Canvas { context, size in
                        let slot = size.width / CGFloat(energy.count)
                        for (index, sample) in energy.enumerated() {
                            let height = max(2, size.height * CGFloat(min(1, max(0, sample))))
                            let rect = CGRect(
                                x: CGFloat(index) * slot,
                                y: size.height - height,
                                width: max(1, slot - 0.3),
                                height: height
                            )
                            context.fill(Path(rect), with: .color(Palette.bili.opacity(0.9)))
                        }
                    }
                    .frame(width: geo.size.width, height: 18)
                    .offset(y: -6)
                }
                if model.flag("显示视频分段信息") {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { _, mark in
                        let start = min(1, max(0, chapterSeconds(mark) / duration))
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * start, y: -4)
                    }
                }
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
                        onScrub(localProgress)
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
        .frame(height: 36)
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
        let name = model.qualityName
        if name.contains("360") { return "360P" }
        if name.contains("480") { return "480P" }
        if name.contains("720") { return "720P" }
        if name.contains("1080") && name.contains("60") { return "1080P60" }
        if name.contains("1080") { return "1080P" }
        if name.contains("4K") || name.contains("2160") { return "4K" }
        return "自动"
    }

    private var offlineFile: Bool { video.playURL?.hasPrefix("file:") == true }

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
            ActionChip(system: model.liked.contains(video.bvid) ? "hand.thumbsup.fill" : "hand.thumbsup", title: actionCount(video.like + (model.liked.contains(video.bvid) ? 1 : 0), word: "赞"), selected: model.liked.contains(video.bvid)) {
                model.toggleLike(video.bvid)
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in model.triple(video.bvid) })
            ActionChip(system: model.disliked.contains(video.bvid) ? "hand.thumbsdown.fill" : "hand.thumbsdown", title: "点踩", selected: model.disliked.contains(video.bvid)) {
                model.toggleDislike(video.bvid)
            }
            ActionChip(system: "bitcoinsign.circle", title: actionCount(video.coin, word: "投币"), selected: model.coined.contains(video.bvid)) {
                coinPick = 2
                showCoin = true
            }
            ActionChip(system: model.favored.contains(video.bvid) ? "star.fill" : "star", title: actionCount(video.favorite, word: "收藏"), selected: model.favored.contains(video.bvid)) {
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
            ActionChip(system: "arrowshape.turn.up.right", title: actionCount(video.share, word: "分享")) { showShare = true }
        }
    }

    private func actionCount(_ value: Int, word: String) -> String {
        if video.playURL?.hasPrefix("file:") == true, value <= 0 { return word }
        return CountText.format(value)
    }
}

/// Sort, paging, and reply threads shared by the video page and a dynamic detail page.
struct CommentThreadList: View {
    @Environment(AppModel.self) private var model
    let oid: Int
    let type: Int
    var embedded: Bool
    @State private var comments: [CommentItem]
    @State private var page: Int
    @State private var hasMore: Bool
    @State private var replyPages: [Int: Int] = [:]
    @State private var draft = ""
    @State private var replyTarget: CommentItem?

    init(oid: Int, type: Int, initial: [CommentItem] = [], embedded: Bool = false) {
        self.oid = oid
        self.type = type
        self.embedded = embedded
        _comments = State(initialValue: initial)
        _page = State(initialValue: initial.count >= 20 ? 2 : 1)
        _hasMore = State(initialValue: initial.count >= 20)
    }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 12) {
                    stack
                    composer
                }
            } else {
                ScrollView { stack.padding(16) }
                    .safeAreaBar(edge: .bottom, spacing: 8) { composer.padding(.horizontal, 16).padding(.vertical, 8) }
            }
        }
        .sheet(item: $replyTarget) { comment in replySheet(comment) }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if oid <= 0 || type <= 0 {
                ContentUnavailableView("还没有评论", systemImage: "text.bubble", description: Text("这条动态没有打开评论区"))
            } else {
                HStack {
                    Text(model.values["评论展示"] ?? "按热度").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.values["评论展示"] == "按时间" ? "按热度" : "按时间") {
                        model.values["评论展示"] = model.values["评论展示"] == "按时间" ? "按热度" : "按时间"
                        model.save()
                        Task { await reload() }
                    }
                    .font(.caption.weight(.semibold))
                }
                VStack(spacing: 0) {
                    ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                        if index > 0 {
                            Divider()
                        }
                        CommentRow(
                            comment: comment,
                            nested: false,
                            plain: true,
                            onReply: { replyTarget = $0 },
                            mention: { draft = "@\($0.name) " },
                            onMore: { item in Task { await loadReplies(item) } }
                        )
                        .onAppear {
                            guard comment.id == comments.last?.id else { return }
                            Task { await loadMore() }
                        }
                    }
                }
                if comments.isEmpty {
                    ContentUnavailableView("还没有评论", systemImage: "text.bubble", description: Text("或者评论区暂时关闭"))
                }
            }
        }
    }

    private var composer: some View {
        HStack {
            TextField(model.flag("记录评论") ? "友善评论…" : "发一条评论", text: $draft)
                .textFieldStyle(.roundedBorder)
            Button("发送") { send(nil) }
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
        }
    }

    private func reload() async {
        guard oid > 0, type > 0 else { return }
        let sort = model.values["评论展示"] == "按时间" ? 0 : 1
        guard let rows = try? await model.client.replies(oid: oid, type: type, page: 1, sort: sort) else { return }
        comments = rows
        page = rows.count >= 20 ? 2 : 1
        hasMore = rows.count >= 20
    }

    private func loadMore() async {
        guard hasMore, oid > 0, type > 0 else { return }
        let sort = model.values["评论展示"] == "按时间" ? 0 : 1
        let fetching = page
        guard let rows = try? await model.client.replies(oid: oid, type: type, page: fetching, sort: sort) else { return }
        let known = Set(comments.map(\.id))
        comments.append(contentsOf: rows.filter { !known.contains($0.id) })
        hasMore = rows.count >= 20
        if hasMore { page = fetching + 1 }
    }

    private func loadReplies(_ comment: CommentItem) async {
        guard oid > 0, type > 0 else { return }
        let next = (replyPages[comment.id] ?? 0) + 1
        guard let more = try? await model.client.replyThread(oid: oid, root: comment.id, page: next, type: type) else { return }
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        if next == 1 {
            comments[index].replies = more
        } else {
            let known = Set(comments[index].replies.map(\.id))
            comments[index].replies.append(contentsOf: more.filter { !known.contains($0.id) })
        }
        replyPages[comment.id] = next
    }

    private func send(_ parent: CommentItem?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, oid > 0, type > 0 else { return }
        let root = parent.map { $0.root == 0 ? $0.id : $0.root } ?? 0
        let parentID = parent?.id ?? 0
        draft = ""
        Task {
            if await model.sendComment(aid: oid, message: text, root: root, parent: parentID, type: type) {
                await reload()
            }
        }
    }

    private func replySheet(_ comment: CommentItem) -> some View {
        GlassMenuSheet(title: comment.name, rows: Menus.replyMenu.map { ("circle", $0) }) { action in
            switch action {
            case "复制":
                UIPasteboard.general.string = comment.message
                model.show("已复制评论")
            case "回复":
                draft = "@\(comment.name) "
            default:
                model.show(action)
            }
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
    /// Dynamic detail uses a flat row. Video comments keep the plate.
    var plain: Bool = false

    var body: some View {
        let row = VStack(alignment: .leading, spacing: plain ? 4 : 6) {
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
                    CommentRow(comment: child, nested: true, onReply: onReply, mention: mention, plain: plain)
                        .padding(.leading, 20)
                }
                if comment.replyCount > comment.replies.count {
                    Button("查看回复 \(CountText.format(comment.replyCount))") { onMore(comment) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, plain ? 8 : 12)
        .padding(.horizontal, plain ? 0 : 12)
        if plain {
            row
        } else {
            row.contentPlate(radius: nested ? 14 : 20)
        }
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
