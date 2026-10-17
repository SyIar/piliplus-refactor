import Foundation

struct VideoPage: Identifiable, Hashable, Codable {
    var id: Int { cid }
    var cid: Int
    var index: Int
    var title: String
    var duration: Int
}

struct VideoItem: Identifiable, Hashable, Codable {
    var id: String { bvid }
    var bvid: String
    var aid: Int
    var cid: Int
    var title: String
    var cover: String
    var duration: Int
    var ownerName: String
    var ownerMid: Int
    var ownerFace: String
    var desc: String
    var pubdate: Int
    var view: Int
    var danmaku: Int
    var like: Int
    var coin: Int
    var favorite: Int
    var share: Int
    var reply: Int
    var pages: [VideoPage]
    var tname: String
    var playURL: String? = nil
    var audioURL: String? = nil
    var qualities: [String] = []
    var qualityIDs: [Int] = []
    var streamCodec: String = ""

    var pageCount: Int { max(pages.count, 1) }

    mutating func apply(_ offer: PlaybackOffer) {
        playURL = offer.videoURL
        audioURL = offer.audioURL
        qualities = offer.qualities
        qualityIDs = offer.qualityIDs
        streamCodec = offer.codec
    }
}

struct CommentItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let face: String
    let message: String
    let like: Int
    let ctime: Int
    let replies: [CommentItem]
}

struct DynamicItem: Identifiable, Hashable {
    let id: String
    let name: String
    let face: String
    let text: String
    let time: String
    let kind: String
    var video: VideoItem?
    var like: Int
    var comment: Int
    var repost: Int
}

struct LiveRoom: Identifiable, Hashable {
    let id: Int
    let title: String
    let cover: String
    let uname: String
    let face: String
    let online: Int
    let area: String
}

struct HotWord: Identifiable, Hashable {
    var id: String { keyword }
    let keyword: String
    let show: String
}

struct InboxItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let systemImage: String
    let unread: Int
}

struct DanmakuCue: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String
    let color: UInt32
    let mode: Int
}
