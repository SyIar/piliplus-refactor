import Foundation

/// Bilibili DASH `.m4s` is a fragmented MP4 (`ftyp` / `iso5`). AVFoundation rejects
/// that container with `AVFoundationErrorDomain` -11828, so this rebuilds one
/// progressive `.mp4` whose samples AVPlayer can open from a `file://` URL.
enum FragmentRemux {
    static func writeMovie(video videoURL: URL, audio audioURL: URL?, to output: URL) throws {
        let videoData = try Data(contentsOf: videoURL)
        let video = try parse(videoData, role: "vide")
        var audio: MediaTrack?
        var audioData: Data?
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            let loaded = try Data(contentsOf: audioURL)
            audio = try parse(loaded, role: "soun")
            audioData = loaded
        }
        let file = try assemble(video: video, videoData: videoData, audio: audio, audioData: audioData)
        let partial = output.appendingPathExtension("part")
        try file.write(to: partial, options: .atomic)
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.moveItem(at: partial, to: output)
        print("offline movie \(file.count) video \(video.samples.count) audio \(audio?.samples.count ?? 0) \(video.entryType)/\(audio?.entryType ?? "-")")
    }

    private static func assemble(video: MediaTrack, videoData: Data, audio: MediaTrack?, audioData: Data?) throws -> Data {
        let videoBytes = try payload(video, from: videoData)
        let audioBytes: Data
        if let audio, let audioData {
            audioBytes = try payload(audio, from: audioData)
        } else {
            audioBytes = Data()
        }
        let audioTrack = audioBytes.isEmpty ? nil : audio
        let payload = videoBytes + audioBytes
        guard payload.count > 10_000 else { throw RemuxError("样本太短") }

        let ftyp = ftypBox()
        let preliminary = try moovBox(video: video, audio: audioTrack, videoOffset: 0, audioOffset: 0)
        let dataStart = ftyp.count + preliminary.count + 8
        guard dataStart + payload.count < Int(UInt32.max) else { throw RemuxError("文件过大") }
        let audioOffset = dataStart + videoBytes.count
        let moov = try moovBox(video: video, audio: audioTrack, videoOffset: dataStart, audioOffset: audioOffset)
        guard moov.count == preliminary.count else { throw RemuxError("索引大小不一致") }

        var output = Data()
        output.reserveCapacity(dataStart + payload.count)
        output.append(ftyp)
        output.append(moov)
        output.addU32(UInt32(8 + payload.count))
        output.addFour("mdat")
        output.append(payload)
        try validate(output, dataStart: dataStart, payload: payload.count, video: video, audio: audioTrack)
        return output
    }

    private static func payload(_ track: MediaTrack, from data: Data) throws -> Data {
        let raw = [UInt8](data)
        var blob = Data()
        blob.reserveCapacity(track.samples.reduce(0) { $0 + Int($1.size) })
        for sample in track.samples {
            let end = sample.offset + Int(sample.size)
            guard sample.offset >= 0, end <= raw.count else { throw RemuxError("样本越界") }
            blob.append(contentsOf: raw[sample.offset..<end])
        }
        return blob
    }

    private static func validate(_ file: Data, dataStart: Int, payload: Int, video: MediaTrack, audio: MediaTrack?) throws {
        let boxes = try boxes(in: file, from: 0, to: file.count)
        let covered = boxes.reduce(0) { $0 + $1.size }
        guard covered == file.count,
              boxes.contains(where: { $0.type == "ftyp" }),
              boxes.contains(where: { $0.type == "moov" }),
              boxes.contains(where: { $0.type == "mdat" }) else { throw RemuxError("封装结构不完整") }
        let mdatEnd = dataStart + payload
        func check(_ track: MediaTrack, _ start: Int) throws {
            var cursor = start
            for sample in track.samples {
                guard cursor >= dataStart, cursor + Int(sample.size) <= mdatEnd else { throw RemuxError("样本偏移无效") }
                cursor += Int(sample.size)
            }
        }
        try check(video, dataStart)
        if let audio {
            try check(audio, dataStart + video.samples.reduce(0) { $0 + Int($1.size) })
        }
    }
}

private struct FragSample {
    var offset: Int
    var size: UInt32
    var duration: UInt32
    var flags: UInt32
    var ctts: Int32
}

private struct MediaTrack {
    var handler: String
    var timescale: UInt32
    var width: UInt32
    var height: UInt32
    var language: UInt16
    var stsd: Data
    var samples: [FragSample]

    var entryType: String {
        guard stsd.count >= 20 else { return "?" }
        return stsd.fourcc(20)
    }
}

private struct SampleDefaults {
    var duration: UInt32 = 0
    var size: UInt32 = 0
    var flags: UInt32 = 0
}

private struct RemuxError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One copy of the downloaded file. `Data` subscripts were slow enough to stall the remux.
private struct MP4File {
    let raw: [UInt8]
    init(_ data: Data) { raw = [UInt8](data) }
    var count: Int { raw.count }

    func u8(_ offset: Int) -> UInt8 { raw[offset] }
    func u16(_ offset: Int) -> UInt16 { UInt16(raw[offset]) << 8 | UInt16(raw[offset + 1]) }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(raw[offset]) << 24 | UInt32(raw[offset + 1]) << 16 | UInt32(raw[offset + 2]) << 8 | UInt32(raw[offset + 3])
    }
    func u64(_ offset: Int) -> UInt64 { UInt64(u32(offset)) << 32 | UInt64(u32(offset + 4)) }
    func i32(_ offset: Int) -> Int32 { Int32(bitPattern: u32(offset)) }
    func fourcc(_ offset: Int) -> String {
        String(bytes: raw[offset..<offset + 4], encoding: .isoLatin1) ?? "????"
    }
    func copy(_ start: Int, _ end: Int) -> Data { Data(raw[start..<end]) }
    func hex(_ offset: Int) -> String {
        guard offset >= 0, offset + 8 <= raw.count else { return "" }
        return raw[offset..<offset + 8].map { String(format: "%02x", $0) }.joined()
    }
}

private extension FragmentRemux {
    static func parse(_ data: Data, role: String) throws -> MediaTrack {
        try parse(file: MP4File(data), role: role)
    }

    static func parse(file data: MP4File, role: String) throws -> MediaTrack {
        guard data.count >= 16, data.fourcc(4) == "ftyp" else { throw RemuxError("不是 fMP4") }
        let top = try boxes(in: data, from: 0, to: data.count)
        var tracks: [UInt32: MediaTrack] = [:]
        var defaults: [UInt32: SampleDefaults] = [:]
        for box in top where box.type == "moov" {
            for child in try boxes(in: data, from: box.payload, to: box.end) {
                if child.type == "mvex" {
                    for trex in try boxes(in: data, from: child.payload, to: child.end) where trex.type == "trex" {
                        let (id, sample) = try readTrex(data, trex)
                        defaults[id] = sample
                    }
                } else if child.type == "trak" {
                    let track = try readTrak(data, child)
                    tracks[track.id] = track.media
                }
            }
        }
        let fragmentCount = top.filter { $0.type == "moof" }.count
        print("offline boxes \(data.count) moof \(fragmentCount) tracks \(tracks.count)")
        var sampleMap: [UInt32: [FragSample]] = [:]
        for box in top where box.type == "moof" {
            for traf in try boxes(in: data, from: box.payload, to: box.end) where traf.type == "traf" {
                let parsed = try readTraf(data, traf, moof: box.start, defaults: defaults)
                guard tracks[parsed.id] != nil else { continue }
                var bucket = sampleMap.removeValue(forKey: parsed.id) ?? []
                bucket.append(contentsOf: parsed.samples)
                sampleMap[parsed.id] = bucket
            }
        }
        var built = tracks
        for (id, samples) in sampleMap {
            guard var media = built[id] else { continue }
            media.samples = samples
            built[id] = media
        }
        let candidates = built.values.filter { !$0.samples.isEmpty }
        let chosen = candidates.first { $0.handler == role }
            ?? candidates.first { role == "vide" ? $0.handler != "soun" : $0.handler == "soun" }
            ?? candidates.first
        guard var track = chosen else { throw RemuxError(role == "soun" ? "没有音频样本" : "没有视频样本") }
        if track.handler.isEmpty { track.handler = role }
        if track.timescale == 0 { throw RemuxError("时间刻度无效") }
        track.stsd = normalized(track.stsd)
        if track.handler == "vide", track.width == 0 || track.height == 0 {
            let size = visualSize(track.stsd)
            track.width = size.width
            track.height = size.height
        }
        let syncs = track.samples.filter { ($0.flags & 0x0001_0000) == 0 }.count
        let head = track.samples.first.map { data.hex($0.offset) } ?? ""
        print("offline remux \(track.handler) samples \(track.samples.count) timescale \(track.timescale) keyframes \(syncs) stsd \(track.entryType) \(head)")
        return track
    }

    static func readTrak(_ data: MP4File, _ trak: Box) throws -> (id: UInt32, media: MediaTrack) {
        var id: UInt32 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var timescale: UInt32 = 0
        var language: UInt16 = 0x55C4
        var handler = ""
        var stsd = Data()
        for child in try boxes(in: data, from: trak.payload, to: trak.end) {
            if child.type == "tkhd" {
                let header = try readTkhd(data, child)
                id = header.id
                width = header.width
                height = header.height
            } else if child.type == "mdia" {
                for mdia in try boxes(in: data, from: child.payload, to: child.end) {
                    if mdia.type == "mdhd" {
                        let header = try readMdhd(data, mdia)
                        timescale = header.timescale
                        language = header.language
                    } else if mdia.type == "hdlr" {
                        handler = readHandler(data, mdia)
                    } else if mdia.type == "minf" {
                        stsd = findBox(data, mdia, name: "stsd")?.bytes(data) ?? Data()
                    }
                }
            }
        }
        guard id > 0 else { throw RemuxError("没有轨道号") }
        if handler.isEmpty { handler = infer(stsd) }
        return (id, MediaTrack(handler: handler, timescale: timescale, width: width, height: height, language: language, stsd: stsd, samples: []))
    }

    static func readTrex(_ data: MP4File, _ box: Box) throws -> (UInt32, SampleDefaults) {
        guard box.payload + 24 <= box.end else { throw RemuxError("trex 太短") }
        let id = data.u32(box.payload + 4)
        return (id, SampleDefaults(
            duration: data.u32(box.payload + 12),
            size: data.u32(box.payload + 16),
            flags: data.u32(box.payload + 20)
        ))
    }

    static func readTraf(_ data: MP4File, _ traf: Box, moof: Int, defaults: [UInt32: SampleDefaults]) throws -> (id: UInt32, samples: [FragSample]) {
        var id: UInt32 = 0
        var base = UInt64(moof)
        var sampleDefault = SampleDefaults()
        var truns: [Box] = []
        for child in try boxes(in: data, from: traf.payload, to: traf.end) {
            if child.type == "tfhd" {
                let header = try readTfhd(data, child, moof: moof)
                id = header.id
                base = header.base
                sampleDefault = header.defaults
            } else if child.type == "trun" {
                truns.append(child)
            }
        }
        if sampleDefault.duration == 0 { sampleDefault.duration = defaults[id]?.duration ?? 0 }
        if sampleDefault.size == 0 { sampleDefault.size = defaults[id]?.size ?? 0 }
        if sampleDefault.flags == 0 { sampleDefault.flags = defaults[id]?.flags ?? 0 }
        var samples: [FragSample] = []
        for trun in truns {
            samples.append(contentsOf: try readTrun(data, trun, base: base, defaults: sampleDefault))
        }
        return (id, samples)
    }

    static func readTfhd(_ data: MP4File, _ box: Box, moof: Int) throws -> (id: UInt32, base: UInt64, defaults: SampleDefaults) {
        guard box.payload + 8 <= box.end else { throw RemuxError("tfhd 太短") }
        let flags = data.u32(box.payload) & 0x00ff_ffff
        var cursor = box.payload + 4
        let id = data.u32(cursor)
        cursor += 4
        var base = UInt64(moof)
        var sample = SampleDefaults()
        if flags & 0x000001 != 0 {
            guard cursor + 8 <= box.end else { throw RemuxError("tfhd 截断") }
            base = data.u64(cursor)
            cursor += 8
        }
        if flags & 0x000002 != 0 { cursor += 4 }
        if flags & 0x000008 != 0 {
            guard cursor + 4 <= box.end else { throw RemuxError("tfhd 截断") }
            sample.duration = data.u32(cursor)
            cursor += 4
        }
        if flags & 0x000010 != 0 {
            guard cursor + 4 <= box.end else { throw RemuxError("tfhd 截断") }
            sample.size = data.u32(cursor)
            cursor += 4
        }
        if flags & 0x000020 != 0 {
            guard cursor + 4 <= box.end else { throw RemuxError("tfhd 截断") }
            sample.flags = data.u32(cursor)
        }
        return (id, base, sample)
    }

    static func readTrun(_ data: MP4File, _ box: Box, base: UInt64, defaults: SampleDefaults) throws -> [FragSample] {
        guard box.payload + 8 <= box.end else { throw RemuxError("trun 太短") }
        let flags = data.u32(box.payload) & 0x00ff_ffff
        var cursor = box.payload + 4
        let count = Int(data.u32(cursor))
        cursor += 4
        var dataOffset: Int32 = 0
        if flags & 0x000001 != 0 {
            guard cursor + 4 <= box.end else { throw RemuxError("trun 截断") }
            dataOffset = data.i32(cursor)
            cursor += 4
        }
        var firstFlags = defaults.flags
        if flags & 0x000004 != 0 {
            guard cursor + 4 <= box.end else { throw RemuxError("trun 截断") }
            firstFlags = data.u32(cursor)
            cursor += 4
        }
        var fieldStride = 0
        if flags & 0x000100 != 0 { fieldStride += 4 }
        if flags & 0x000200 != 0 { fieldStride += 4 }
        if flags & 0x000400 != 0 { fieldStride += 4 }
        if flags & 0x000800 != 0 { fieldStride += 4 }
        let fits = fieldStride > 0 ? max(0, box.end - cursor) / fieldStride : count
        print("offline trun count \(count) flags \(String(flags, radix: 16)) bytes \(box.size) fits \(fits)")
        guard count > 0, count <= 400_000, count <= fits else { throw RemuxError("样本数量异常 \(count)") }
        let origin = Int64(base) + Int64(dataOffset)
        guard origin >= 0 else { throw RemuxError("样本偏移为负") }
        var sampleCursor = Int(origin)
        var local = cursor
        var samples: [FragSample] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            var duration = defaults.duration
            var size = defaults.size
            var sampleFlags = index == 0 ? firstFlags : defaults.flags
            var ctts: Int32 = 0
            if flags & 0x000100 != 0 { duration = try pullU32(data.raw, &local) }
            if flags & 0x000200 != 0 { size = try pullU32(data.raw, &local) }
            if flags & 0x000400 != 0 { sampleFlags = try pullU32(data.raw, &local) }
            if flags & 0x000800 != 0 { ctts = Int32(bitPattern: try pullU32(data.raw, &local)) }
            if duration == 0 { duration = defaults.duration == 0 ? 1 : defaults.duration }
            guard size > 0 else { continue }
            samples.append(FragSample(offset: sampleCursor, size: size, duration: duration, flags: sampleFlags, ctts: ctts))
            sampleCursor += Int(size)
        }
        return samples
    }

    static func readTkhd(_ data: MP4File, _ box: Box) throws -> (id: UInt32, width: UInt32, height: UInt32) {
        guard box.payload + 4 <= box.end else { throw RemuxError("tkhd 太短") }
        let version = data.u8(box.payload)
        let idOffset = version == 1 ? 20 : 12
        let widthOffset = version == 1 ? 88 : 76
        guard box.payload + widthOffset + 8 <= box.end else { throw RemuxError("tkhd 太短") }
        return (data.u32(box.payload + idOffset), data.u32(box.payload + widthOffset), data.u32(box.payload + widthOffset + 4))
    }

    static func readMdhd(_ data: MP4File, _ box: Box) throws -> (timescale: UInt32, language: UInt16) {
        guard box.payload + 4 <= box.end else { throw RemuxError("mdhd 太短") }
        let version = data.u8(box.payload)
        let scale = version == 1 ? 20 : 12
        let language = version == 1 ? 32 : 20
        guard box.payload + language + 2 <= box.end else { throw RemuxError("mdhd 太短") }
        return (data.u32(box.payload + scale), data.u16(box.payload + language))
    }

    static func readHandler(_ data: MP4File, _ box: Box) -> String {
        guard box.payload + 12 <= box.end else { return "" }
        return data.fourcc(box.payload + 8)
    }

    static func infer(_ stsd: Data) -> String {
        guard stsd.count >= 20 else { return "" }
        switch stsd.fourcc(20) {
        case "mp4a", "ac-3", "ec-3", "alac", "Opus", "fLaC": return "soun"
        case "avc1", "avc3", "hvc1", "hev1", "av01", "mp4v": return "vide"
        default: return ""
        }
    }

    static func findBox(_ data: MP4File, _ root: Box, name: String) -> Box? {
        guard let children = try? boxes(in: data, from: root.payload, to: root.end) else { return nil }
        for child in children {
            if child.type == name { return child }
            if ["minf", "stbl", "dinf", "mdia"].contains(child.type), let found = findBox(data, child, name: name) {
                return found
            }
        }
        return nil
    }

    static func normalized(_ stsd: Data) -> Data {
        guard stsd.count > 16 else { return stsd }
        var bytes = [UInt8](stsd)
        let count = Int(stsd.u32(12))
        var offset = 16
        for _ in 0..<count {
            guard offset + 16 <= bytes.count else { break }
            let entrySize = Int(stsd.u32(offset))
            guard entrySize >= 16, offset + entrySize <= bytes.count else { break }
            bytes[offset + 14] = 0
            bytes[offset + 15] = 1
            offset += entrySize
        }
        return Data(bytes)
    }

    static func visualSize(_ stsd: Data) -> (width: UInt32, height: UInt32) {
        guard stsd.count >= 16 + 36 else { return (640 << 16, 360 << 16) }
        let width = UInt32(stsd.u16(16 + 32))
        let height = UInt32(stsd.u16(16 + 34))
        guard width > 0, height > 0 else { return (640 << 16, 360 << 16) }
        return (width << 16, height << 16)
    }

    static func ftypBox() -> Data {
        var body = Data()
        body.addFour("isom")
        body.addU32(0x200)
        for brand in ["isom", "iso2", "avc1", "mp41"] { body.addFour(brand) }
        return box("ftyp", body)
    }

    static func moovBox(video: MediaTrack, audio: MediaTrack?, videoOffset: Int, audioOffset: Int) throws -> Data {
        let videoMovie = movieDuration(video)
        let audioMovie = audio.map(movieDuration) ?? 0
        let duration = max(videoMovie, audioMovie)
        guard duration > 0, duration <= UInt64(UInt32.max) else { throw RemuxError("时长无效") }
        var body = Data()
        body.append(mvhd(duration: UInt32(duration), nextTrack: audio == nil ? 2 : 3))
        body.append(try trak(video, id: 1, offset: videoOffset, sound: false))
        if let audio {
            body.append(try trak(audio, id: 2, offset: audioOffset, sound: true))
        }
        return box("moov", body)
    }

    static func movieDuration(_ track: MediaTrack) -> UInt64 {
        let media = track.samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) }
        guard track.timescale > 0 else { return 0 }
        return max(1, media * 1000 / UInt64(track.timescale))
    }

    static func mvhd(duration: UInt32, nextTrack: UInt32) -> Data {
        var body = Data()
        body.addU32(0)
        body.addU32(0)
        body.addU32(1000)
        body.addU32(duration)
        body.addU32(0x0001_0000)
        body.addU16(0x0100)
        body.addU16(0)
        body.addU32(0)
        body.addU32(0)
        body.append(identityMatrix())
        body.append(Data(count: 24))
        body.addU32(nextTrack)
        return full("mvhd", body)
    }

    static func trak(_ track: MediaTrack, id: UInt32, offset: Int, sound: Bool) throws -> Data {
        var body = Data()
        body.append(tkhd(track, id: id, sound: sound))
        body.append(try mdia(track, offset: offset, sound: sound))
        return box("trak", body)
    }

    static func tkhd(_ track: MediaTrack, id: UInt32, sound: Bool) -> Data {
        let duration = UInt32(movieDuration(track))
        var body = Data()
        body.addU32(0)
        body.addU32(0)
        body.addU32(id)
        body.addU32(0)
        body.addU32(duration)
        body.addU32(0)
        body.addU32(0)
        body.addU16(0)
        body.addU16(sound ? 1 : 0)
        body.addU16(sound ? 0x0100 : 0)
        body.addU16(0)
        body.append(identityMatrix())
        body.addU32(sound ? 0 : track.width)
        body.addU32(sound ? 0 : track.height)
        return full("tkhd", body, flags: 0x7)
    }

    static func mdia(_ track: MediaTrack, offset: Int, sound: Bool) throws -> Data {
        let media = track.samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) }
        guard media <= UInt64(UInt32.max) else { throw RemuxError("媒体时长过长") }
        var body = Data()
        body.append(mdhd(timescale: track.timescale, duration: UInt32(media), language: track.language))
        body.append(hdlr(sound: sound))
        body.append(try minf(track, offset: offset, sound: sound))
        return box("mdia", body)
    }

    static func mdhd(timescale: UInt32, duration: UInt32, language: UInt16) -> Data {
        var body = Data()
        body.addU32(0)
        body.addU32(0)
        body.addU32(timescale)
        body.addU32(duration)
        body.addU16(language == 0 ? 0x55C4 : language)
        body.addU16(0)
        return full("mdhd", body)
    }

    static func hdlr(sound: Bool) -> Data {
        var body = Data()
        body.addU32(0)
        body.addFour(sound ? "soun" : "vide")
        body.addU32(0)
        body.addU32(0)
        body.addU32(0)
        let name = sound ? "SoundHandler" : "VideoHandler"
        body.append(contentsOf: name.utf8)
        body.append(0)
        return full("hdlr", body)
    }

    static func minf(_ track: MediaTrack, offset: Int, sound: Bool) throws -> Data {
        var body = Data()
        body.append(sound ? smhd() : vmhd())
        body.append(dinf())
        body.append(try stbl(track, offset: offset, sound: sound))
        return box("minf", body)
    }

    static func vmhd() -> Data {
        var body = Data()
        body.addU16(0)
        body.addU16(0)
        body.addU16(0)
        body.addU16(0)
        return full("vmhd", body, flags: 1)
    }

    static func smhd() -> Data {
        var body = Data()
        body.addU16(0)
        body.addU16(0)
        return full("smhd", body)
    }

    static func dinf() -> Data {
        let url = full("url ", Data(), flags: 1)
        var drefBody = Data()
        drefBody.addU32(1)
        drefBody.append(url)
        return box("dinf", full("dref", drefBody))
    }

    static func stbl(_ track: MediaTrack, offset: Int, sound: Bool) throws -> Data {
        guard track.stsd.count > 16, track.stsd.fourcc(4) == "stsd" else { throw RemuxError("没有样本描述") }
        var body = Data()
        body.append(track.stsd)
        body.append(stts(track.samples))
        body.append(stsc(track.samples.count))
        body.append(stsz(track.samples))
        body.append(stco(track.samples, offset: offset))
        if !sound, let sync = stss(track.samples) { body.append(sync) }
        return box("stbl", body)
    }

    static func stts(_ samples: [FragSample]) -> Data {
        var body = Data()
        let runs = durationRuns(samples)
        body.addU32(UInt32(runs.count))
        for run in runs {
            body.addU32(run.count)
            body.addU32(run.delta)
        }
        return full("stts", body)
    }

    /// One sample per chunk, paired with one `stco` offset per sample.
    static func stsc(_ sampleCount: Int) -> Data {
        var body = Data()
        body.addU32(1)
        body.addU32(1)
        body.addU32(sampleCount > 0 ? 1 : 0)
        body.addU32(1)
        return full("stsc", body)
    }

    static func stsz(_ samples: [FragSample]) -> Data {
        var body = Data()
        body.addU32(0)
        body.addU32(UInt32(samples.count))
        for sample in samples { body.addU32(sample.size) }
        return full("stsz", body)
    }

    static func stco(_ samples: [FragSample], offset: Int) -> Data {
        var body = Data()
        body.addU32(UInt32(samples.count))
        var cursor = offset
        for sample in samples {
            body.addU32(UInt32(cursor))
            cursor += Int(sample.size)
        }
        return full("stco", body)
    }

    static func stss(_ samples: [FragSample]) -> Data? {
        var numbers: [UInt32] = []
        for (index, sample) in samples.enumerated() where (sample.flags & 0x0001_0000) == 0 {
            numbers.append(UInt32(index + 1))
        }
        if numbers.isEmpty { numbers = [1] }
        if numbers.count == samples.count { return nil }
        var body = Data()
        body.addU32(UInt32(numbers.count))
        for number in numbers { body.addU32(number) }
        return full("stss", body)
    }

    static func durationRuns(_ samples: [FragSample]) -> [(count: UInt32, delta: UInt32)] {
        var runs: [(count: UInt32, delta: UInt32)] = []
        for sample in samples {
            if let last = runs.last, last.delta == sample.duration {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((1, sample.duration))
            }
        }
        return runs
    }

    static func identityMatrix() -> Data {
        var body = Data()
        for value in [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] as [UInt32] {
            body.addU32(value)
        }
        return body
    }

    static func box(_ type: String, _ payload: Data) -> Data {
        var out = Data()
        out.addU32(UInt32(8 + payload.count))
        out.addFour(type)
        out.append(payload)
        return out
    }

    static func full(_ type: String, _ body: Data, version: UInt8 = 0, flags: UInt32 = 0) -> Data {
        var payload = Data()
        payload.addU32((UInt32(version) << 24) | (flags & 0x00ff_ffff))
        payload.append(body)
        return box(type, payload)
    }
}

private struct Box {
    var start: Int
    var size: Int
    var header: Int
    var type: String
    var payload: Int { start + header }
    var end: Int { start + size }

    func bytes(_ data: MP4File) -> Data { data.copy(start, end) }
}

private func pullU32(_ table: [UInt8], _ index: inout Int) throws -> UInt32 {
    guard index + 4 <= table.count else { throw RemuxError("trun 截断") }
    let value = UInt32(table[index]) << 24 | UInt32(table[index + 1]) << 16 | UInt32(table[index + 2]) << 8 | UInt32(table[index + 3])
    index += 4
    return value
}

private func boxes(in data: MP4File, from: Int, to: Int) throws -> [Box] {
    var offset = from
    var result: [Box] = []
    while offset + 8 <= to {
        if result.count > 100_000 { throw RemuxError("盒子过多") }
        let size32 = data.u32(offset)
        let type = data.fourcc(offset + 4)
        var header = 8
        var size = Int(size32)
        if size32 == 1 {
            guard offset + 16 <= to else { throw RemuxError("盒子被截断") }
            let large = data.u64(offset + 8)
            guard large <= UInt64(Int.max) else { throw RemuxError("盒子过大") }
            size = Int(large)
            header = 16
        } else if size32 == 0 {
            size = to - offset
        }
        guard size >= header, offset + size <= to else { throw RemuxError("盒子 \(type) 损坏") }
        result.append(Box(start: offset, size: size, header: header, type: type))
        offset += size
    }
    return result
}

private extension Data {
    func u8(_ offset: Int) -> UInt8 { self[offset] }
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) << 8 | UInt16(self[offset + 1]) }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16 | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }
    func u64(_ offset: Int) -> UInt64 { UInt64(u32(offset)) << 32 | UInt64(u32(offset + 4)) }
    func i32(_ offset: Int) -> Int32 { Int32(bitPattern: u32(offset)) }
    func fourcc(_ offset: Int) -> String {
        String(bytes: self[offset..<offset + 4], encoding: .isoLatin1) ?? "????"
    }

    mutating func addU16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xff))
    }

    mutating func addU32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func addFour(_ text: String) {
        var bytes = Array(text.utf8.prefix(4))
        if bytes.count < 4 { bytes.append(contentsOf: repeatElement(0, count: 4 - bytes.count)) }
        append(contentsOf: bytes)
    }
}
