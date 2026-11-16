import Foundation

struct Emoji: Identifiable, Hashable {
    let shortcode: String
    let char: String
    var id: String { shortcode }
}

/// Emoji database built from Unicode character names plus common Slack/GitHub style aliases.
final class EmojiStore {
    static let shared = EmojiStore()

    private(set) var all: [Emoji] = []
    private var byCode: [String: Emoji] = [:]

    private let usageKey = "emojiUsage"
    private var usage: [String: Int]

    private init() {
        usage = UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int] ?? [:]

        var dict: [String: String] = [:]
        let ranges: [ClosedRange<UInt32>] = [
            0x1F000...0x1FAFF, 0x2190...0x21FF, 0x2300...0x23FF,
            0x25A0...0x27BF, 0x2900...0x297F, 0x2B00...0x2BFF, 0x3030...0x303D, 0x3297...0x3299,
        ]
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                if (0x1F1E6...0x1F1FF).contains(value) || (0x1F3FB...0x1F3FF).contains(value) { continue }
                let props = scalar.properties
                guard props.isEmoji, let name = props.name else { continue }
                let char = props.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
                let code = Self.shortcode(from: name)
                if dict[code] == nil { dict[code] = char }
            }
        }
        for (code, char) in Self.aliases {
            dict[code] = char
        }
        all = dict.map { Emoji(shortcode: $0.key, char: $0.value) }.sorted { $0.shortcode < $1.shortcode }
        byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.shortcode, $0) })
    }

    private static func shortcode(from name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastUnderscore = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastUnderscore = false
            } else if !lastUnderscore && !out.isEmpty {
                out.append("_")
                lastUnderscore = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out
    }

    func exact(_ code: String) -> Emoji? { byCode[code.lowercased()] }

    func usageCount(_ emoji: Emoji) -> Int { usage[emoji.char] ?? 0 }

    func recordUse(_ emoji: Emoji) {
        usage[emoji.char, default: 0] += 1
        UserDefaults.standard.set(usage, forKey: usageKey)
    }

    func resetUsage() {
        usage = [:]
        UserDefaults.standard.removeObject(forKey: usageKey)
    }

    var frequentlyUsed: [Emoji] {
        let top = usage.sorted { $0.value > $1.value }.prefix(16).map(\.key)
        return top.compactMap { char in all.first { $0.char == char } }
    }

    func search(_ rawQuery: String, limit: Int = 8) -> [Emoji] {
        let query = rawQuery.lowercased()
        guard !query.isEmpty else { return [] }

        var scored: [(Emoji, Int)] = []
        for emoji in all {
            let code = emoji.shortcode
            let score: Int
            if code == query { score = 0 }
            else if code.hasPrefix(query) { score = 1 }
            else if code.contains("_" + query) { score = 2 }
            else if code.contains(query) { score = 3 }
            else { continue }
            scored.append((emoji, score))
        }
        scored.sort { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            let ua = usageCount(a.0), ub = usageCount(b.0)
            if ua != ub { return ua > ub }
            if a.0.shortcode.count != b.0.shortcode.count { return a.0.shortcode.count < b.0.shortcode.count }
            return a.0.shortcode < b.0.shortcode
        }

        var seen = Set<String>()
        var results: [Emoji] = []
        for (emoji, _) in scored where !seen.contains(emoji.char) {
            seen.insert(emoji.char)
            results.append(emoji)
            if results.count == limit { break }
        }
        return results
    }

    // Array (not dictionary literal) so duplicate keys are harmless.
    private static let aliases: [(String, String)] = [
        ("smile", "😄"), ("smiley", "😃"), ("grin", "😁"), ("joy", "😂"), ("rofl", "🤣"),
        ("laughing", "😆"), ("wink", "😉"), ("blush", "😊"), ("heart_eyes", "😍"), ("kissing_heart", "😘"),
        ("thinking", "🤔"), ("sweat_smile", "😅"), ("slightly_smiling_face", "🙂"), ("upside_down", "🙃"),
        ("sob", "😭"), ("cry", "😢"), ("rage", "😡"), ("angry", "😠"), ("scream", "😱"),
        ("sunglasses", "😎"), ("nerd", "🤓"), ("neutral_face", "😐"), ("expressionless", "😑"),
        ("unamused", "😒"), ("roll_eyes", "🙄"), ("smirk", "😏"), ("sleeping", "😴"), ("mask", "😷"),
        ("skull", "💀"), ("ghost", "👻"), ("poop", "💩"), ("hankey", "💩"), ("clown", "🤡"), ("robot", "🤖"),
        ("alien", "👽"), ("sweat", "😓"), ("relieved", "😌"), ("yum", "😋"), ("stuck_out_tongue", "😛"),
        ("stuck_out_tongue_winking_eye", "😜"), ("zany", "🤪"), ("money_mouth", "🤑"), ("shush", "🤫"),
        ("zipper_mouth", "🤐"), ("exploding_head", "🤯"), ("mind_blown", "🤯"), ("cowboy", "🤠"),
        ("star_struck", "🤩"), ("innocent", "😇"), ("smiling_imp", "😈"), ("imp", "👿"),
        ("hugs", "🤗"), ("hugging", "🤗"), ("partying_face", "🥳"), ("party", "🥳"), ("pleading", "🥺"),
        ("melting_face", "🫠"), ("salute", "🫡"), ("see_no_evil", "🙈"), ("hear_no_evil", "🙉"),
        ("speak_no_evil", "🙊"), ("shrug", "🤷"), ("man_shrugging", "🤷‍♂️"), ("woman_shrugging", "🤷‍♀️"),
        ("facepalm", "🤦"), ("+1", "👍"), ("thumbsup", "👍"), ("thumbs_up", "👍"), ("-1", "👎"),
        ("thumbsdown", "👎"), ("thumbs_down", "👎"), ("ok_hand", "👌"), ("clap", "👏"), ("wave", "👋"),
        ("raised_hands", "🙌"), ("pray", "🙏"), ("muscle", "💪"), ("point_up", "☝️"), ("point_down", "👇"),
        ("point_left", "👈"), ("point_right", "👉"), ("v", "✌️"), ("crossed_fingers", "🤞"),
        ("handshake", "🤝"), ("writing_hand", "✍️"), ("heart_hands", "🫶"), ("eyes", "👀"), ("brain", "🧠"),
        ("heart", "❤️"), ("red_heart", "❤️"), ("orange_heart", "🧡"), ("yellow_heart", "💛"),
        ("green_heart", "💚"), ("blue_heart", "💙"), ("purple_heart", "💜"), ("black_heart", "🖤"),
        ("white_heart", "🤍"), ("broken_heart", "💔"), ("sparkling_heart", "💖"), ("two_hearts", "💕"),
        ("heart_on_fire", "❤️‍🔥"), ("fire", "🔥"), ("sparkles", "✨"), ("star", "⭐"), ("star2", "🌟"),
        ("zap", "⚡"), ("boom", "💥"), ("tada", "🎉"), ("confetti_ball", "🎊"), ("balloon", "🎈"),
        ("gift", "🎁"), ("trophy", "🏆"), ("rocket", "🚀"), ("100", "💯"), ("white_check_mark", "✅"),
        ("check", "✔️"), ("heavy_check_mark", "✔️"), ("x", "❌"), ("warning", "⚠️"), ("question", "❓"),
        ("exclamation", "❗"), ("bangbang", "‼️"), ("no_entry", "⛔"), ("no_entry_sign", "🚫"),
        ("bulb", "💡"), ("memo", "📝"), ("pencil", "✏️"), ("pencil2", "✏️"), ("calendar", "📅"),
        ("email", "📧"), ("phone", "📱"), ("iphone", "📱"), ("computer", "💻"), ("bug", "🐛"),
        ("wrench", "🔧"), ("hammer", "🔨"), ("gear", "⚙️"), ("lock", "🔒"), ("unlock", "🔓"), ("key", "🔑"),
        ("link", "🔗"), ("coffee", "☕"), ("tea", "🍵"), ("beer", "🍺"), ("beers", "🍻"), ("wine_glass", "🍷"),
        ("pizza", "🍕"), ("cake", "🍰"), ("birthday", "🎂"), ("taco", "🌮"), ("popcorn", "🍿"),
        ("avocado", "🥑"), ("cheese", "🧀"), ("apple", "🍎"), ("banana", "🍌"), ("sunny", "☀️"),
        ("sun", "☀️"), ("cloud", "☁️"), ("rain", "🌧️"), ("snowflake", "❄️"), ("rainbow", "🌈"),
        ("moon", "🌙"), ("earth_africa", "🌍"), ("earth_americas", "🌎"), ("earth_asia", "🌏"),
        ("dog", "🐶"), ("cat", "🐱"), ("unicorn", "🦄"), ("ok", "🆗"), ("cool", "🆒"), ("new", "🆕"),
        ("free", "🆓"), ("sos", "🆘"), ("moneybag", "💰"), ("money", "💰"), ("dollar", "💵"),
        ("chart_with_upwards_trend", "📈"), ("chart_with_downwards_trend", "📉"), ("hourglass", "⌛"),
        ("hourglass_flowing_sand", "⏳"), ("alarm_clock", "⏰"), ("bell", "🔔"), ("mega", "📣"),
        ("loudspeaker", "📢"), ("pushpin", "📌"), ("paperclip", "📎"), ("books", "📚"), ("book", "📖"),
        ("ship", "🚢"), ("airplane", "✈️"), ("car", "🚗"), ("red_car", "🚗"), ("house", "🏠"),
        ("checkered_flag", "🏁"), ("white_flag", "🏳️"), ("rainbow_flag", "🏳️‍🌈"), ("pirate_flag", "🏴‍☠️"),
        ("gb", "🇬🇧"), ("uk", "🇬🇧"), ("flag_gb", "🇬🇧"), ("us", "🇺🇸"), ("flag_us", "🇺🇸"),
        ("fr", "🇫🇷"), ("de", "🇩🇪"), ("jp", "🇯🇵"), ("es", "🇪🇸"), ("it", "🇮🇹"), ("cn", "🇨🇳"),
        ("kr", "🇰🇷"), ("ca", "🇨🇦"), ("au", "🇦🇺"), ("in", "🇮🇳"), ("br", "🇧🇷"), ("ie", "🇮🇪"),
        ("ship_it", "🚢"), ("shipit", "🐿️"), ("lgtm", "👍"), ("thank_you", "🙏"), ("thanks", "🙏"),
    ]
}
