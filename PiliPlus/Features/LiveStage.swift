import AVFoundation
import SwiftUI

struct LiveStage: View {
    @Environment(AppModel.self) private var model
    let roomID: Int
    @State private var room: LiveRoom?
    @State private var offer: LiveOffer?
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var playedSeconds = 0.0
    @State private var playError = ""
    @State private var text = ""
    @State private var fullscreen = false
    @State private var feed = LiveDanmuFeed()
    @State private var clockToken: Any?
    @State private var streams: [String] = []
    @State private var streamIndex = 0
    @State private var quietPolls = 0
    @State private var progressMark = 0.0
    @State private var loggedPlayer = false

    var body: some View {
        stage
            .background(fullscreen ? Color.black : Color(.systemBackground))
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(fullscreen ? .hidden : .visible, for: .tabBar)
            .statusBarHidden(fullscreen)
            .task(id: roomID) { await load() }
            .task { await prove() }
            .onDisappear {
                if let player, let clockToken {
                    player.removeTimeObserver(clockToken)
                }
                player?.pause()
                feed.stop()
            }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            playerBlock
                .frame(height: fullscreen ? nil : 230)
                .frame(maxHeight: fullscreen ? .infinity : 230)
            if !fullscreen {
                header
                chat
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                composer
            }
        }
    }

    private var playerBlock: some View {
        ZStack {
            Color.black
            if let player {
                PlayerSurface(player: player, pipEnabled: model.flag("后台画中画"))
            } else if let cover = room?.cover, !cover.isEmpty {
                RemoteImage(url: cover).opacity(0.45)
            }
            if model.danmakuOn {
                LiveDanmakuOverlay(lines: feed.lines)
            }
            if player == nil && playError.isEmpty {
                ProgressView("正在连接直播")
                    .tint(.white)
            }
            LivePlayerChrome(
                title: room?.title ?? "直播",
                quality: offer?.selectedName ?? "",
                qualities: offer?.qualities ?? [],
                playing: playing,
                fullscreen: $fullscreen,
                onPlay: togglePlay,
                onQuality: { name in Task { await switchQuality(name) } }
            )
        }
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RemoteImage(url: room?.face ?? "", ratio: 1, maxPixel: 120)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(room?.title ?? "直播间 \(roomID)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(headerLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var headerLine: String {
        let name = room?.uname ?? "主播"
        let area = room?.area ?? "直播"
        let online = CountText.format(room?.online ?? 0)
        return "\(name) · \(area) · \(online) 人气"
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(feed.count > 0 ? "\(feed.count) 条弹幕" : "弹幕")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            if feed.lines.isEmpty {
                ContentUnavailableView("等待弹幕", systemImage: "text.bubble", description: Text("连上直播间后，弹幕会出现在这里"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(feed.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if !line.name.isEmpty {
                                Text(line.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.bili)
                                    .lineLimit(1)
                            }
                            Text(line.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        .id(line.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: feed.lines.count) { _, _ in
                        if let last = feed.lines.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("发个弹幕…", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
            Button("发送") { Task { await send() } }
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func load() async {
        playError = ""
        if room == nil {
            room = model.lives.first { $0.id == roomID }
        }
        if let info = try? await model.client.liveRoomInfo(room: roomID) {
            room = info
        }
        do {
            let next: LiveOffer
            if let cached = model.liveOffers[roomID], cached.protocolName == "hls" {
                next = cached
            } else {
                next = try await model.client.livePlay(room: roomID, qn: 10_000)
            }
            offer = next
            model.liveOffers[roomID] = next
            streams = [next.url] + next.alternates
            streamIndex = 0
            quietPolls = 0
            progressMark = 0
            startPlayback(next.url)
            print("live play \(next.protocolName) \(next.selectedName) room \(roomID)")
        } catch {
            playError = error.localizedDescription
            print("live play failed \(playError)")
        }
        if let info = try? await model.client.liveDanmuInfo(room: roomID) {
            feed.connect(room: roomID, info: info)
            print("live danmu hosts \(info.hosts.count)")
        } else {
            print("live danmu info failed")
        }
        writeProof()
    }

    private func startPlayback(_ raw: String) {
        guard let url = URL(string: raw) else {
            playError = "直播地址无效"
            return
        }
        let headers = BiliHTTP.liveAssetHeaders(room: roomID)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        if player == nil {
            let created = AVPlayer(playerItem: item)
            created.automaticallyWaitsToMinimizeStalling = true
            player = created
            attachClock(created)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.play()
        playing = true
        playError = ""
        loggedPlayer = false
        print("live stream \(streamIndex) \(url.host ?? "")")
        watch(item)
    }

    private func watch(_ item: AVPlayerItem) {
        Task { @MainActor in
            for _ in 0..<24 {
                try? await Task.sleep(for: .milliseconds(400))
                if item.status == .readyToPlay {
                    player?.play()
                    return
                }
                if item.status == .failed {
                    playError = item.error?.localizedDescription ?? "播放失败"
                    print("live play failed \(playError)")
                    writeProof()
                    return
                }
            }
        }
    }

    private func attachClock(_ player: AVPlayer) {
        if let clockToken {
            player.removeTimeObserver(clockToken)
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        clockToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                if time.seconds.isFinite { playedSeconds = time.seconds }
                writeProof()
            }
        }
    }

    private func togglePlay() {
        if playing {
            player?.pause()
            playing = false
        } else {
            player?.play()
            playing = true
        }
    }

    private func switchQuality(_ name: String) async {
        guard let offer else { return }
        let qn: Int
        if let index = offer.qualities.firstIndex(of: name), offer.qualityIDs.indices.contains(index) {
            qn = offer.qualityIDs[index]
        } else {
            qn = LiveRequest.qn(for: name)
        }
        do {
            let next = try await model.client.livePlay(room: roomID, qn: qn)
            self.offer = next
            model.liveOffers[roomID] = next
            streams = [next.url] + next.alternates
            streamIndex = 0
            quietPolls = 0
            progressMark = 0
            startPlayback(next.url)
            model.show("已切换\(next.selectedName)")
        } catch {
            model.show(error.localizedDescription)
        }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let ok = await model.sendLiveDanmaku(room: roomID, message: body)
        if ok { text = "" }
    }

    private func prove() async {
        while !Task.isCancelled {
            sampleClock()
            recoverIfStalled()
            writeProof()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func sampleClock() {
        guard let time = player?.currentTime().seconds, time.isFinite, time >= 0 else { return }
        playedSeconds = time
        if !loggedPlayer, let item = player?.currentItem, item.status == .readyToPlay || item.status == .failed {
            loggedPlayer = true
            let waiting = player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
            print("live clock \(String(format: "%.2f", time)) rate \(player?.rate ?? 0) waiting \(waiting)")
        }
        if player?.rate == 0, playing, playError.isEmpty {
            player?.play()
        }
    }

    /// A stalled HLS host is swapped for the next candidate. The clock is sampled from the new item.
    private func recoverIfStalled() {
        guard offer != nil, playError.isEmpty, !streams.isEmpty else { return }
        if playedSeconds > progressMark + 0.35 {
            progressMark = playedSeconds
            quietPolls = 0
            return
        }
        quietPolls += 1
        guard quietPolls >= 20, streamIndex + 1 < streams.count else { return }
        streamIndex += 1
        quietPolls = 0
        progressMark = 0
        print("live stall \(String(format: "%.2f", playedSeconds)) try \(streamIndex)")
        startPlayback(streams[streamIndex])
    }

    private func writeProof() {
        let seconds = playedSeconds.isFinite ? playedSeconds : 0
        LiveRoomProof.record([
            "room": room?.id ?? roomID,
            "title": room?.title ?? "",
            "uname": room?.uname ?? "",
            "online": room?.online ?? 0,
            "protocol": offer?.protocolName ?? "",
            "quality": offer?.selectedName ?? "",
            "seconds": seconds,
            "danmaku": feed.count,
            "error": playError
        ])
    }
}

private struct LiveDanmakuOverlay: View {
    let lines: [LiveChatLine]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                let now = context.date
                let visible = lines.suffix(16).filter { now.timeIntervalSince($0.born) < 8 }
                ForEach(Array(visible.enumerated()), id: \.element.id) { _, line in
                    let age = now.timeIntervalSince(line.born)
                    let lane = abs(line.id.hashValue) % 5
                    let x = geo.size.width * (1.05 - min(age, 8) / 8 * 1.25)
                    Text(line.text)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                        .lineLimit(1)
                        .position(x: x, y: CGFloat(18 + lane * 22))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LivePlayerChrome: View {
    @Environment(AppModel.self) private var model
    let title: String
    let quality: String
    let qualities: [String]
    let playing: Bool
    @Binding var fullscreen: Bool
    var onPlay: () -> Void
    var onQuality: (String) -> Void
    @State private var chrome = true
    @State private var chromeToken = 0

    private var pinsChrome: Bool { LaunchMode.screen == "live-room" }

    var body: some View {
        ZStack {
            Color.black.opacity(chrome ? 0.18 : 0)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleChrome() }
            if chrome {
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.22), value: chrome)
        .onAppear { armHide() }
    }

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0).allowsHitTesting(false)
                bottomRow
            }
            Button(action: {
                onPlay()
                reveal()
            }) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "暂停" : "播放")
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            iconButton("chevron.backward") { goBack() }
                .accessibilityLabel("返回")
            Text("LIVE")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.bili, in: Capsule())
                .foregroundStyle(.white)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(.leading, 8)
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
        }
        .padding(.horizontal, 2)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 88)
                .allowsHitTesting(false)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 4)
            iconButton(model.danmakuOn ? "text.bubble.fill" : "text.bubble") {
                model.danmakuOn.toggle()
                model.setFlag("弹幕开关", model.danmakuOn)
                reveal()
            }
            .accessibilityLabel(model.danmakuOn ? "关闭弹幕" : "打开弹幕")
            if !qualities.isEmpty {
                Menu {
                    ForEach(qualities, id: \.self) { name in
                        Button {
                            onQuality(name)
                            reveal()
                        } label: {
                            if quality == name {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    Text(quality.isEmpty ? "画质" : quality)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .accessibilityLabel("画质")
            }
            iconButton(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                withAnimation(.easeOut(duration: 0.25)) { fullscreen.toggle() }
                reveal()
            }
            .accessibilityLabel(fullscreen ? "退出全屏" : "全屏")
        }
        .padding(.bottom, 4)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 88)
                .allowsHitTesting(false)
        }
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
        chrome.toggle()
        if chrome { armHide() }
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
            guard token == chromeToken else { return }
            chrome = false
        }
    }
}
