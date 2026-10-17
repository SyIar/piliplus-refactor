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
    /// Playback position in seconds. `-1` means the history item was finished.
    var progress: Int = 0
    var viewAt: Int = 0
    var collectionTitle: String = ""
    var collectionIndex: Int = 0
    var collectionCount: Int = 0
    var collectionClips: [CollectionClip] = []

    var pageCount: Int { max(pages.count, 1) }

    mutating func apply(_ offer: PlaybackOffer) {
        playURL = offer.videoURL
        audioURL = offer.audioURL
        qualities = offer.qualities
        qualityIDs = offer.qualityIDs
        streamCodec = offer.codec
    }
}

struct CollectionClip: Codable, Hashable, Identifiable {
    var id: String { bvid.isEmpty ? "\(index)" : bvid }
    var bvid: String
    var title: String
    var index: Int
}

struct FavFolder: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var count: Int
    var favored: Bool
}

struct SeasonItem: Identifiable, Hashable {
    var id: Int { seasonID }
    var seasonID: Int
    var title: String
    var cover: String
    var badge: String
    var subtitle: String
    var view: Int
}

struct CommentItem: Identifiable, Hashable {
    var id: Int
    var name: String
    var face: String
    var message: String
    var like: Int
    var ctime: Int
    var replies: [CommentItem]
    var replyCount: Int = 0
    var root: Int = 0
}

struct SearchUser: Identifiable, Hashable {
    var id: Int { mid }
    var mid: Int
    var name: String
    var face: String
    var fans: Int
    var sign: String
}

struct SearchPage {
    var videos: [VideoItem]
    var users: [SearchUser]
    var seasons: [SeasonItem]
    var lives: [LiveRoom]
    var articles: [SearchArticle]
    /// Set when a type search came back with rows we could not read.
    var note: String = ""
}

struct SearchArticle: Identifiable, Hashable {
    var id: Int
    var title: String
    var summary: String
    var cover: String
    var author: String
    var view: Int
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
