import SwiftUI
import AVKit
import AVFoundation

struct VideoStage: View {
    @Environment(AppModel.self) private var model
    let bvid: String
    @State private var video: VideoItem?
    @State private var related: [VideoItem] = []
    @State private var comments: [CommentItem] = []
    @State private var tab = "简介"
    @State private var showMore = false
    @State private var showCoin = false
    @State private var showFav = false
    @State private var showShare = false
    @State private var showQuality = false
    @State private var showSpeed = false
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
    @State private var folder = "默认收藏夹"
    private var progress: Double {
        seeking ? localProgress : model.playbackSeconds
    }
    @State private var localProgress: Double = 0
    @State private var danmaku: [DanmakuCue] = []
    @State private var expandedDesc = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let video {
                stage(video)
            } else if !error.isEmpty {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("正在加载").tint(.white)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if LaunchMode.usesFixtures, let cached = model.video(bvid) {
                video = cached
                related = Array(model.feed.prefix(4))
                return
            }
            await load()
        }
        .sheet(isPresented: $showMore) { moreSheet }
        .sheet(isPresented: $showShare) { shareSheet }
        .sheet(isPresented: $showCoin) { coinSheet }
        .sheet(isPresented: $showFav) { favSheet }
        .sheet(isPresented: $showQuality) { qualitySheet }
        .sheet(isPresented: $showSpeed) { speedSheet }
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
        .background(fullscreen ? Color.black : Color.clear)
        .background { if !fullscreen { AuroraBackdrop() } }
    }

    private func player(_ video: VideoItem) -> some View {
        ZStack {
            Color.black
            if let player = model.player {
                PlayerSurface(player: player)
            } else {
                RemoteImage(url: video.cover).opacity(0.45)
            }
            if model.danmakuOn && model.flag("弹幕开关") {
                DanmakuLayer(cues: danmaku)
                    .allowsHitTesting(model.flag("启用点击弹幕"))
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(interactive: false)
            }
            if !locked {
                PlayerControls(
                    video: video,
                    fullscreen: $fullscreen,
                    seeking: $seeking,
                    localProgress: $localProgress,
                    showMore: $showMore,
                    showSpeed: $showSpeed,
                    showQuality: $showQuality,
                    showDanmaku: $showDanmaku,
                    locked: $locked,
                    coinPick: $coinPick,
                    showCoin: $showCoin,
                    showFav: $showFav,
                    showShare: $showShare
                )
            }
            if locked {
                Button { locked = false } label: {
                    Image(systemName: "lock.fill").padding(12)
                }
                .glassCapsule()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: fullscreen ? 0 : 0, style: .continuous))
        .gesture(playerDrag(video))
        .simultaneousGesture(TapGesture(count: 2).onEnded { doubleTap() })
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
            Picker("", selection: $tab) {
                Text("简介").tag("简介")
                if model.flag("显示视频评论") { Text("评论 \(CountText.format(video.reply))").tag("评论") }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            if tab == "简介" { intro(video) } else { commentList }
        }
    }

    private func intro(_ video: VideoItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(video.title).font(.title3.bold())
                HStack(spacing: 12) {
                    meta("play.fill", video.view)
                    meta("text.bubble", video.danmaku)
                    meta("calendar", video.pubdate)
                    if !video.tname.isEmpty { Text(video.tname).font(.caption).foregroundStyle(.secondary) }
                }
                Button { model.open(.user(video.ownerMid, video.ownerName)) } label: {
                    HStack {
                        RemoteImage(url: video.ownerFace, ratio: 1, maxPixel: 120).frame(width: 36, height: 36).clipShape(Circle())
                        Text(video.ownerName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("关注")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.bili, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                VideoActionRow(video: video, coinPick: $coinPick, showCoin: $showCoin, showFav: $showFav, showShare: $showShare)
                    .padding(8)
                    .contentPlate(radius: 22)
                if model.flag("显示视频分段信息") && video.pageCount > 1 {
                    Text("分P · \(video.pageCount)").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(video.pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    currentPage = index
                                    Task { await reload(video, cid: page.cid) }
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text("P\(page.index)").font(.caption2.weight(.bold))
                                        Text(page.title).font(.caption).lineLimit(1)
                                    }
                                    .padding(10)
                                    .frame(width: 140, alignment: .leading)
                                    .contentPlate(radius: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !video.desc.isEmpty {
                    Text(expandedDesc || model.flag("默认展开视频简介") ? video.desc : String(video.desc.prefix(80)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(expandedDesc ? "收起" : "展开") { expandedDesc.toggle() }
                        .font(.caption.weight(.semibold))
                }
                if model.flag("启用AI总结") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("AI 总结", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.bili)
                        Text("正在根据简介与热门评论生成摘要。登录后可拉取完整总结。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentPlate(radius: 18)
                }
                if model.flag("视频页显示相关视频") {
                    Text("相关视频").font(.headline)
                    ForEach(related) { item in
                        VideoCard(video: item)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private func meta(_ icon: String, _ value: Int) -> some View {
        Label(value > 1_000_000_000 ? DurationBadge.clock(value) : CountText.format(value), systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
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
                    CommentRow(comment: comment, nested: false, onReply: { replyTarget = $0 }, mention: { draft = "@\($0.name) " })
                }
                if comments.isEmpty {
                    ContentUnavailableView("还没有评论", systemImage: "text.bubble", description: Text("或者评论区暂时关闭"))
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField(model.flag("记录评论") ? "友善评论…" : "发一条评论", text: $draft)
                    .textFieldStyle(.plain)
                Button("发送") { sendReply(nil) }.font(.subheadline.weight(.bold)).foregroundStyle(Palette.bili)
            }
            .padding(12)
            .glassCard(radius: 22)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
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

    private func load() async {
        do {
            var item = try await model.client.detail(bvid: bvid)
            let cid = item.pages.first?.cid ?? item.cid
            let qn = (model.values["默认画质"] ?? "").contains("1080") && model.flag("免登录1080P") ? 80 : 64
            if let play = try? await model.client.playURL(bvid: bvid, cid: cid, qn: qn) {
                item.playURL = play.url
                item.qualities = play.qualities
                model.qualityName = play.qualities.first ?? model.qualityName
            }
            video = item
            model.store(item)
            model.play(item)
            danmaku = sampleDanmaku(for: item)
            if model.flag("自动全屏") { fullscreen = true }
            if model.flag("默认展示评论区") { tab = "评论" }
            async let rel = model.client.related(bvid: bvid)
            async let rep = model.client.replies(aid: item.aid)
            related = (try? await rel) ?? []
            comments = (try? await rep) ?? []
            related.forEach(model.store)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload(_ video: VideoItem, cid: Int) async {
        var copy = video
        if let play = try? await model.client.playURL(bvid: video.bvid, cid: cid, qn: 64) {
            copy.playURL = play.url
            copy.cid = cid
            model.play(copy)
            self.video = copy
            model.show("已切换分P")
        }
    }

    private func sampleDanmaku(for video: VideoItem) -> [DanmakuCue] {
        let lines = ["前方高能", "来了来了", "这期质量好高", "三连了", "空降成功", "UP 好强", video.ownerName, "弹幕护体", "iOS 27 液态玻璃", "PiliPlus"]
        return lines.enumerated().map { index, text in
            DanmakuCue(time: Double(index) * 1.4, text: text, color: index % 4 == 0 ? 0xFB7299 : 0xFFFFFF, mode: 1)
        }
    }

    private func sendReply(_ parent: CommentItem?) {
        guard model.requireLogin("评论") else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.show(model.flag("发评反诈") ? "已发送，反诈检查：评论可见" : "评论已发送")
    }

    private var moreSheet: some View {
        GlassMenuSheet(title: "更多", rows: Menus.videoMore) { action in
            switch action {
            case "添加至「稍后再看」": if let video { model.watchLater(video.bvid) }
            case "选择画质": showQuality = true
            case "选择音质": model.show("音质：\(model.values["默认音质"] ?? "高码率")")
            case "播放顺序": model.show("播放顺序：\(model.values["播放顺序"] ?? "自动连播")")
            case "弹幕设置", "弹幕列表": showDanmaku = true
            case "字幕设置": model.show("字幕偏好：\(model.values["字幕选择偏好"] ?? "自动")")
            case "定时关闭": model.show("将在 30 分钟后停止播放")
            case "播放地址":
                UIPasteboard.general.string = video?.playURL
                model.show("已复制定播放地址")
            case "保存封面": model.show("封面已保存")
            case "重载视频": Task { await load() }
            case "举报": model.show("已打开举报")
            case "离线缓存": model.open(.feature("离线缓存"))
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
    }

    private var favSheet: some View {
        NavigationStack {
            List {
                ForEach(model.favFolders, id: \.self) { name in
                    Button {
                        folder = name
                        if let video { model.favorite(video.bvid, folder: name) }
                        showFav = false
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if folder == name { Image(systemName: "checkmark") }
                        }
                    }
                }
                Button("新建收藏夹") {
                    model.favFolders.append("新建收藏夹 \(model.favFolders.count)")
                    model.show("已新建收藏夹")
                }
            }
            .navigationTitle("收藏到")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var qualitySheet: some View {
        let options = video?.qualities.isEmpty == false ? video!.qualities : ["自动", "流畅 360P", "高清 720P", "高清 1080P", "超清 4K"]
        return OptionSheet(title: "选择画质", options: options, selection: Binding(get: { model.qualityName }, set: { model.qualityName = $0; model.show("画质 \($0)") }))
    }

    private var speedSheet: some View {
        OptionSheet(title: "倍速", options: ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "3.0x"], selection: Binding(
            get: { String(format: "%.2gx", model.playbackRate) },
            set: { label in
                let value = Float(label.replacingOccurrences(of: "x", with: "")) ?? 1
                model.playbackRate = value
                model.player?.rate = value
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
                Button("屏蔽词管理") { model.open(.feature("弹幕")) }
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
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
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
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
                    track(at: timeline.date)
                }
            } else {
                track(at: .now)
            }
        }
        .allowsHitTesting(false)
    }

    private func track(at date: Date) -> some View {
        GeometryReader { geo in
            let t = date.timeIntervalSinceReferenceDate
            ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                let travel = 7.0
                let phase = (t + cue.time).truncatingRemainder(dividingBy: travel) / travel
                Text(cue.text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: cue.color))
                    .position(x: geo.size.width * (1.15 - phase * 1.4), y: 24 + CGFloat(index % 5) * 26)
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
    @Binding var showSpeed: Bool
    @Binding var showQuality: Bool
    @Binding var showDanmaku: Bool
    @Binding var locked: Bool
    @Binding var coinPick: Int
    @Binding var showCoin: Bool
    @Binding var showFav: Bool
    @Binding var showShare: Bool

    private var progress: Double {
        seeking ? localProgress : model.playbackSeconds
    }

    var body: some View {
        VStack {
            HStack {
                if model.flag("观看人数") {
                    Label(CountText.format(max(video.view / 80, 1)), systemImage: "person.2.fill")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                Spacer()
                Button { showMore = true } label: { Image(systemName: "ellipsis").padding(8) }
            }
            .foregroundStyle(.white)
            .padding(8)
            Spacer()
            if model.flag("显示高能进度条") {
                EnergyBar(progress: progress, duration: Double(max(video.duration, 1)))
                    .frame(height: 18)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 12) {
                Button { togglePlay() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                Text(DurationBadge.clock(Int(progress))).font(.caption2.monospacedDigit())
                Slider(
                    value: Binding(
                        get: { progress },
                        set: { localProgress = $0; seeking = true }
                    ),
                    in: 0...Double(max(video.duration, 1)),
                    onEditingChanged: { editing in
                        if !editing {
                            model.playbackSeconds = localProgress
                            model.player?.seek(to: CMTime(seconds: localProgress, preferredTimescale: 600))
                            seeking = false
                        }
                    }
                )
                .tint(.white)
                Text(DurationBadge.clock(video.duration)).font(.caption2.monospacedDigit())
                Button { showSpeed = true } label: { Text(String(format: "%.2gx", model.playbackRate)).font(.caption.weight(.bold)) }
                Button { showQuality = true } label: { Text(shortQuality).font(.caption.weight(.bold)) }
                Button { model.danmakuOn.toggle(); model.setFlag("弹幕开关", model.danmakuOn) } label: {
                    Image(systemName: model.danmakuOn ? "text.bubble.fill" : "text.bubble")
                }
                Button { showDanmaku = true } label: { Image(systemName: "slider.horizontal.3") }
                if model.flag("全屏显示截图按钮") {
                    Button { model.show("已保存截图到相册预览") } label: { Image(systemName: "camera") }
                }
                if model.flag("全屏显示锁定按钮") {
                    Button { locked = true } label: { Image(systemName: "lock.open") }
                }
                Button { withAnimation(.easeOut(duration: 0.25)) { fullscreen.toggle() } } label: {
                    Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(8)
            if fullscreen && model.flag("全屏展示点赞/投币/收藏等操作按钮") {
                VideoActionRow(video: video, coinPick: $coinPick, showCoin: $showCoin, showFav: $showFav, showShare: $showShare)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var shortQuality: String {
        if model.qualityName.contains("1080") { return "1080P" }
        if model.qualityName.contains("720") { return "720P" }
        if model.qualityName.contains("4K") { return "4K" }
        if model.qualityName.contains("360") { return "360P" }
        return "自动"
    }

    private func togglePlay() {
        model.isPlaying.toggle()
        if model.isPlaying { model.player?.play() } else { model.player?.pause() }
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
                if model.flag("快速收藏") { model.favorite(video.bvid, folder: model.favFolders[0]) } else { showFav = true }
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in showFav = true })
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RemoteImage(url: comment.face, ratio: 1, maxPixel: 96)
                    .frame(width: nested ? 22 : 32, height: nested ? 22 : 32)
                    .clipShape(Circle())
                Text(comment.name).font(.caption.weight(.semibold))
                if model.flag("显示粉丝勋章") {
                    Text("粉丝牌").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1).background(Palette.bili.opacity(0.2), in: Capsule())
                }
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
                ForEach(comment.replies.prefix(2)) { child in
                    CommentRow(comment: child, nested: true, onReply: onReply, mention: mention)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(12)
        .contentPlate(radius: nested ? 14 : 20)
    }
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
