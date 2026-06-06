import SwiftUI

/// A rare "guest star" cameo: one of Bryan + Victoria's favorite artists drops by the
/// companion card as an Easter egg. They appear *occasionally on a good day* (see
/// `CameoDirector`), reuse the same `CompanionMood` + blink machinery as the regular
/// companion, and — when tapped — blurt one of their real signature catchphrases.
///
/// Roster: Peso + Tito are the hand-authored pixel-grid sprites (`PixelArtists.swift`);
/// JOP + Chuyin are ChatGPT-made art rendered from sliced PNG frames in the asset catalog
/// (`<name>_base` / `_blink` / `_talk`). (Alejandro is the rival — a separate system, not in
/// this random cameo roster.)
enum ArtistCameo: String, CaseIterable {
    case peso
    case tito
    case jop
    case chuyin

    var displayName: String {
        switch self {
        case .peso: return "Peso Pluma"
        case .tito: return "Tito Doble P"
        case .jop: return "JOP"
        case .chuyin: return "Chuyin"
        }
    }

    /// Real signature adlibs/catchphrases (kept short + clean for the speech bubble).
    var lines: [String] {
        switch self {
        case .peso: return ["¡Ja-ja!", "Doble P 💪", "¡Ja, au!"]
        case .tito: return ["Puro Doble P", "¡Ay mamá!"]
        case .jop: return ["¡Fuer-za Regida!", "No pasa nada 💛"]
        // TODO: confirm Chuyin's real lines with Bryan (placeholder — Street Mob / money humor).
        case .chuyin: return ["Puro Street Mob 😎", "Billetes pa' las metas 💸"]
        }
    }

    /// A random line, avoiding an immediate repeat of `last`.
    func randomLine(excluding last: String?) -> String {
        let pool = lines.filter { $0 != last }
        return (pool.isEmpty ? lines : pool).randomElement() ?? lines.first ?? ""
    }

    /// The guest portrait (no fixed frame — the caller sizes it), reflecting blink + talk.
    /// Peso/Tito are pixel-grid sprites; JOP/Chuyin are PNG frames (base/blink/talk). Guests
    /// are always cheerful (they only ever drop by on a good day).
    @ViewBuilder
    func portrait(blinking: Bool, talking: Bool) -> some View {
        switch self {
        case .peso:
            PixelArtView(rows: PixelPeso.rows(mood: .happy, eyesOpen: !blinking), palette: PixelPeso.palette)
        case .tito:
            PixelArtView(rows: PixelTito.rows(mood: .happy, eyesOpen: !blinking), palette: PixelTito.palette)
        case .jop, .chuyin:
            Image(imageFrame(blinking: blinking, talking: talking))
                .resizable()
                .scaledToFit()
        }
    }

    /// Asset name for a PNG-frame guest: `<name>_talk` while speaking, else `_blink` / `_base`.
    private func imageFrame(blinking: Bool, talking: Bool) -> String {
        if talking { return "\(rawValue)_talk" }
        if blinking { return "\(rawValue)_blink" }
        return "\(rawValue)_base"
    }
}

/// Decides *when* a guest cameo appears — "rare, but not too rare." Standard gacha-style
/// pity timer so it never spams and never goes dry:
///   • **Floor** — at least `minDaysApart` days between cameos (keeps it special).
///   • **Trigger** — only on a "good day" (she hit her fuel goal), so a cameo == a reward.
///   • **Chance** — a modest `chance` per qualifying day, capped to ONE roll/day.
///   • **Pity** — guaranteed once `pityDays` have passed with none (and on the very first
///     good day ever, as a one-time discovery moment).
///   • **Rotate** — never the same guest twice in a row.
///
/// `evaluate` mutates the profile (records the roll / the shown guest) and returns the
/// guest active *today*, or nil. Idempotent within a day: once decided, repeat calls just
/// return today's result without re-rolling.
enum CameoDirector {
    // Tuned for "at least ~twice a week": a guest is GUARANTEED within `pityDays` (even on a
    // quiet day, and on the very first run) and may appear sooner on a good day. `minDaysApart`
    // keeps two from landing back-to-back so each still feels like a treat.
    static let minDaysApart = 2
    static let pityDays = 3
    static let chance = 0.5

    static func evaluate(profile: UserProfile,
                         isGoodDay: Bool,
                         now: Date = .now,
                         calendar: Calendar = .current) -> ArtistCameo? {
        // 1. A guest is already showing today → keep showing the same one.
        if calendar.isDate(profile.lastCameoDate, inSameDayAs: now) {
            return ArtistCameo(rawValue: profile.lastCameoArtistRaw)
        }
        let daysSince = calendar.dateComponents([.day],
                                                from: calendar.startOfDay(for: profile.lastCameoDate),
                                                to: calendar.startOfDay(for: now)).day ?? Int.max

        // 2. Pity ceiling — once it's been `pityDays`, a guest drops by no matter what. This is
        //    what guarantees "at least twice a week" and makes the very first one actually appear.
        if daysSince >= pityDays { return show(profile, now) }

        // 3. Otherwise it's a good-day reward: one roll per day, respecting the floor.
        guard isGoodDay else { return nil }
        if calendar.isDate(profile.lastCameoRollDate, inSameDayAs: now) { return nil }
        profile.lastCameoRollDate = now
        guard daysSince >= minDaysApart else { return nil }
        guard Double.random(in: 0..<1) < chance else { return nil }
        return show(profile, now)
    }

    /// Pick the next guest (rotate; never repeat the last one) and record the visit.
    private static func show(_ profile: UserProfile, _ now: Date) -> ArtistCameo {
        let pick = nextArtist(after: ArtistCameo(rawValue: profile.lastCameoArtistRaw))
        profile.lastCameoDate = now
        profile.lastCameoArtistRaw = pick.rawValue
        return pick
    }

    static func nextArtist(after last: ArtistCameo?) -> ArtistCameo {
        let pool = ArtistCameo.allCases
        guard let last, let idx = pool.firstIndex(of: last) else { return pool.first ?? .peso }
        return pool[(idx + 1) % pool.count]
    }

    #if DEBUG
    /// DEBUG-only: force a guest via launch argument (`--cameo-peso` / `--cameo-tito`) so the
    /// cameo can be screenshot-verified without waiting for the pity timer. Compiled out of Release.
    static func debugForced() -> ArtistCameo? {
        let args = CommandLine.arguments
        // `--cameo-<name>` (simctl), e.g. --cameo-peso / --cameo-jop / --cameo-chuyin.
        for a in args where a.hasPrefix("--cameo-") {
            if let c = ArtistCameo(rawValue: String(a.dropFirst("--cameo-".count))) { return c }
        }
        // maestro passes `arguments: {cameo: jop}` as ["-cameo", "jop"].
        if let i = args.firstIndex(of: "-cameo"), i + 1 < args.count {
            return ArtistCameo(rawValue: args[i + 1])
        }
        return nil
    }
    #endif
}
