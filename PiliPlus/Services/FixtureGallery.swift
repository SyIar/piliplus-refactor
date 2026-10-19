import UIKit

/// Local covers so simulator runs do not depend on the network.
/// Images are large JPEGs on purpose: scrolling them shows decode cost.
enum FixtureGallery {
    static func make() -> (videos: [VideoItem], lives: [LiveRoom], words: [HotWord], dynamics: [DynamicItem]) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pili-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let titles = [
            "液态玻璃下的推荐流", "iPhone 18 Pro 安全区", "滚动时的封面解码", "动态卡片间距",
            "搜索筛选胶囊", "播放器手势", "稍后再看", "每周必看",
            "分区排行", "直播广场", "评论列表", "高能进度条"
        ]
        var videos: [VideoItem] = []
        for index in 0..<24 {
            let file = directory.appendingPathComponent("cover-\(index).jpg")
            if !FileManager.default.fileExists(atPath: file.path) {
                writeCover(index: index, to: file)
            }
            let title = "\(titles[index % titles.count]) \(index + 1)"
            videos.append(VideoItem(
                bvid: String(format: "BV1fixture%04d", index),
                aid: 1000 + index,
                cid: 2000 + index,
                title: title,
                cover: file.absoluteString,
                duration: 70 + index * 37,
                ownerName: index.isMultiple(of: 2) ? "玻璃试验室" : "PiliPlus",
                ownerMid: 8000 + index,
                ownerFace: file.absoluteString,
                desc: "用于模拟器截图和滚动采样的本地条目。",
                pubdate: 1_700_000_000 + index * 3600,
                view: 12_000 + index * 8_400,
                danmaku: 300 + index * 40,
                like: 900 + index * 70,
                coin: 100 + index * 5,
                favorite: 200 + index * 9,
                share: 40 + index,
                reply: 20 + index * 3,
                pages: [],
                tname: "科技"
            ))
        }
        let lives: [LiveRoom] = (0..<6).map { index in
            LiveRoom(
                id: 50_000 + index,
                title: "直播 \(titles[index])",
                cover: videos[index].cover,
                uname: videos[index].ownerName,
                face: videos[index].cover,
                online: 1_200 + index * 860,
                area: ["游戏", "音乐", "知识", "电台"][index % 4]
            )
        }
        let words = ["液态玻璃", "iPhone 18 Pro", "滚动优化", "冷启动", "分P", "弹幕"].map {
            HotWord(keyword: $0, show: $0)
        }
        let dynamics = videos.prefix(8).enumerated().map { offset, video in
            DynamicItem(
                id: video.bvid,
                name: video.ownerName,
                face: video.ownerFace,
                text: video.desc,
                time: offset == 0 ? "刚刚" : "\(offset)小时前",
                kind: "投稿",
                video: video,
                like: video.like,
                comment: video.reply,
                repost: video.share,
                mid: video.ownerMid
            )
        }
        return (videos, lives, words, dynamics)
    }

    private static func writeCover(index: Int, to url: URL) {
        let size = CGSize(width: 1280, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.82) { context in
            let hue = CGFloat(index % 12) / 12
            UIColor(hue: hue, saturation: 0.42, brightness: 0.92, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 460, width: 1280, height: 260))
            let title = "PiliPlus \(index + 1)" as NSString
            title.draw(
                at: CGPoint(x: 64, y: 280),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 92, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
            )
        }
        try? data.write(to: url, options: .atomic)
    }
}
