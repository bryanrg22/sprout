import SwiftUI

/// Which pixel avatar a profile's solo companion uses (Bryan picks `.bryan`,
/// Victoria `.victoria`). The shared buddy character is always the panda.
enum CompanionAvatar: String, Codable, CaseIterable { case victoria, bryan }

/// A hand-authored **pixel-art companion modeled on Victoria** — long dark hair,
/// her signature thin glasses, warm skin, a friendly smile, an olive top and a
/// little gold necklace. It's drawn from a character grid (no image assets), so
/// it stays crisp at any size, animates (blink), and reads on the dark theme.
///
/// Design choice: the character keeps her OWN natural colors; her *mood* is shown
/// through expression (eyes / mouth / cheeks) — the surrounding vitality ring,
/// halo and aura glyph in `CompanionCard` carry the mood color. So she always
/// looks like *her*, never recolored.
///
/// Health-positive, like the rest of the app: the lowest mood is a gentle
/// "sleepy / a little hungry", never a sad or shamed face.
enum PixelVictoria {

    // MARK: Palette
    //
    // One color per grid character. '.' is transparent. Tuned warm so she reads
    // as herself against the near-black canvas.
    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.27, green: 0.18, blue: 0.11),   // hair (warm dark brown)
        "h": Color(red: 0.44, green: 0.30, blue: 0.18),   // hair highlight strand
        "S": Color(red: 0.81, green: 0.59, blue: 0.43),   // skin (warm tan)
        "K": Color(red: 0.69, green: 0.47, blue: 0.33),   // skin shadow
        "G": Color(red: 0.86, green: 0.71, blue: 0.44),   // glasses frame (thin gold)
        "E": Color(red: 0.13, green: 0.09, blue: 0.08),   // eyes
        "C": Color(red: 0.92, green: 0.56, blue: 0.55),   // cheek blush
        "M": Color(red: 0.58, green: 0.26, blue: 0.26),   // mouth / smile
        "T": Color(red: 0.36, green: 0.41, blue: 0.21),   // olive top
        "t": Color(red: 0.28, green: 0.32, blue: 0.16),   // olive top shadow
        "N": Color(red: 0.92, green: 0.76, blue: 0.41),   // necklace (gold)
        "b": Color(red: 0.14, green: 0.10, blue: 0.09),   // eyebrow (hair tone)
        "W": Color(red: 0.98, green: 0.98, blue: 0.99),   // eye catch-light
    ]

    // MARK: Sprite grid (16 wide × 18 tall)
    //
    // Rows are fixed for hair / face / body; the eye row (8) and mouth row (11)
    // are swapped per mood/blink in `rows(mood:eyesOpen:)`.

    private static let base: [String] = [
        ".......HHHHHH.......",  // 0  crown
        ".....HHHHhhHHHH.....",  // 1  center part
        "....HHHHhhhhHHHH....",  // 2
        "...HHHHHHHHHHHHHH...",  // 3
        "..HHHHHHHHHHHHHHHH..",  // 4
        "..HHHHSSSSSSSSHHHH..",  // 5  hairline / forehead
        "..HHHSSSSSSSSSSHHH..",  // 6
        "..HHSSbbSSSSbbSSHH..",  // 7  eyebrows
        "..HHSSSSSSSSSSSSHH..",  // 8  (glasses removed — bare face)
        "..HHSSWESSSSWESSHH..",  // 9  eyes (swapped per blink)
        "..HHSSSSSSSSSSSSHH..",  // 10
        "..HHSSCSSSSSSCSSHH..",  // 11 cheeks
        "..HHSSSSMMMMSSSSHH..",  // 12 mouth (swapped per mood)
        "...HHSSSSSSSSSSHH...",  // 13 chin — open jaw, hair falls at sides
        "...HHHHSSSSSSHHHH...",  // 14 neck (hair beside, never under the chin)
        "..HHHTTTTTTTTTTHHH..",  // 15 shoulders, hair over the outer shoulder
        "..HHTTTTTNNTTTTTHH..",  // 16 collar + necklace
        ".HHhTTTTTTTTTTTThHH.",  // 17 LONG hair falling past the shoulders
        ".HHHTTTTTTTTTTTTHHH.",  // 18
        ".HHhTTTTTTTTTTTThHH.",  // 19
        "..HHHTTTTTTTTTTHHH..",  // 20 hair tapering
        "...HHHTTTTTTTTHHH...",  // 21
        "...HHH........HHH...",  // 22 long hair tips below the torso
        "....HH........HH....",  // 23
    ]

    /// Build the sprite for a mood, with eyes open or closed (blink / sleepy).
    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base

        // Eyes: glossy (catch-light + pupil) when open; soft closed lids otherwise.
        g[9] = eyesOpen ? "..HHSSWESSSSWESSHH.." : "..HHSSEESSSSEESSHH.."

        // Mouth varies with mood (always kind — no frown anywhere).
        switch mood {
        case .thriving, .happy:
            g[12] = "..HHSSSSMMMMSSSSHH.."   // wide beaming smile
        case .content:
            g[12] = "..HHSSSSSMMSSSSSHH.."   // gentle smile
        case .sleepy:
            g[12] = "..HHSSSSSMMSSSSSHH.."   // small calm mouth
        case .hungry:
            g[12] = "..HHSSSSSMMSSSSSHH.."   // soft small mouth (never sad)
        }

        return g
    }
}

// MARK: - Renderer

/// Renders a character grid as crisp pixels with a `Canvas`. Sizes the pixels to
/// fit the available space while preserving the sprite's aspect ratio.
struct PixelArtView: View {
    let rows: [String]
    var palette: [Character: Color]

    var body: some View {
        Canvas { ctx, size in
            let cols = rows.map(\.count).max() ?? 0
            let rowCount = rows.count
            guard cols > 0, rowCount > 0 else { return }

            // Largest square pixel that fits.
            let px = min(size.width / CGFloat(cols), size.height / CGFloat(rowCount))

            // Center the DRAWN content (its non-transparent bounding box), NOT the raw grid.
            // Grids carry asymmetric whitespace, so centering the grid leaves the character
            // visibly off-center in its frame — which made labels/habitats look misaligned and,
            // worse, made idle scale/rotate ("breathing"/"wiggle") pivot about the frame center
            // instead of the character's center, so the sprite appeared to swing/drift sideways.
            // Centering the content box fixes alignment AND keeps the animation in place.
            var minC = cols, maxC = -1, minR = rowCount, maxR = -1
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() where ch != "." && palette[ch] != nil {
                    if c < minC { minC = c }; if c > maxC { maxC = c }
                    if r < minR { minR = r }; if r > maxR { maxR = r }
                }
            }
            let originX: CGFloat, originY: CGFloat
            if maxC >= minC && maxR >= minR {
                let contentCX = CGFloat(minC + maxC + 1) / 2     // center of content box, in cells
                let contentCY = CGFloat(minR + maxR + 1) / 2
                originX = size.width / 2 - contentCX * px
                originY = size.height / 2 - contentCY * px
            } else {
                originX = (size.width - px * CGFloat(cols)) / 2  // empty grid → fall back to grid-center
                originY = (size.height - px * CGFloat(rowCount)) / 2
            }

            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = palette[ch], ch != "." else { continue }
                    // +0.6 overdraw closes hairline seams between adjacent pixels.
                    let rect = CGRect(x: originX + CGFloat(c) * px,
                                      y: originY + CGFloat(r) * px,
                                      width: px + 0.6, height: px + 0.6)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 0), with: .color(color))
                }
            }
        }
        .drawingGroup() // flatten to one layer; keeps the pixels sharp + cheap
    }
}

/// The companion as pixel-Victoria, reflecting a `CompanionMood`.
struct PixelVictoriaView: View {
    let mood: CompanionMood
    /// Eyes open when true; closed for a blink or the sleepy resting state.
    var eyesOpen: Bool = true

    var body: some View {
        PixelArtView(rows: PixelVictoria.rows(mood: mood, eyesOpen: eyesOpen),
                     palette: PixelVictoria.palette)
            // 20:24 sprite — keep that ratio so she isn't stretched.
            .frame(width: 120, height: 144)
            .accessibilityHidden(true) // CompanionCard supplies the spoken label
    }
}

// MARK: - Pixel Bryan (his companion)

/// Pixel-art modeled on Bryan — black wavy hair, warm skin, thick brows, a
/// mustache + soft goatee, a dark tee. Same renderer + mood/blink swap as Victoria.
enum PixelBryan {
    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.20, green: 0.14, blue: 0.10),   // hair (dark brown)
        "h": Color(red: 0.37, green: 0.27, blue: 0.18),   // hair curl highlight (warm)
        "S": Color(red: 0.80, green: 0.57, blue: 0.41),   // skin (warm tan)
        "K": Color(red: 0.66, green: 0.45, blue: 0.31),   // skin shadow / jaw
        "E": Color(red: 0.12, green: 0.09, blue: 0.08),   // eyes
        "W": Color(red: 0.98, green: 0.98, blue: 0.99),   // eye catch-light
        "b": Color(red: 0.11, green: 0.10, blue: 0.11),   // thick brow
        "F": Color(red: 0.16, green: 0.13, blue: 0.12),   // facial hair (mustache/goatee)
        "M": Color(red: 0.50, green: 0.24, blue: 0.22),   // mouth
        "D": Color(red: 0.21, green: 0.21, blue: 0.24),   // dark tee
        "d": Color(red: 0.13, green: 0.13, blue: 0.16),   // tee shadow
        "C": Color(red: 0.88, green: 0.89, blue: 0.93),   // silver Cuban chain + cross
        "P": Color(red: 0.33, green: 0.22, blue: 0.14),   // brown scapular (escapulario)
    ]

    private static let base: [String] = [
        "....HHhHHHHHhH......",  // 0  curly top (warm curl shine)
        "..HHhHHHHHhHHHHH....",  // 1  voluminous + texture
        ".HHHHHHHHHHHHHHHHH..",  // 2  widest, fluffy
        ".HHhHHHHHHHHHhHHHH..",  // 3  curl texture
        ".HHHHHHHHHHHHHHHHHH.",  // 4
        "..HHHHSSSSSSSSHHHH..",  // 5  hairline / forehead
        "...HSSSSSSSSSSSSH...",  // 6  tapered / faded sides (1px)
        "...HSSbbSSSSbbSSH...",  // 7  eyebrows
        "....SSSSSSSSSSSS....",  // 8  faded sides → skin
        "....SSWESSSSWESS....",  // 9  eyes (swapped per blink)
        "....SSSSSSSSSSSS....",  // 10
        "....SSSSFFFFSSSS....",  // 11 small mustache (no goatee)
        "....SSSSMMMMSSSS....",  // 12 mouth (swapped per mood)
        ".....SSSSSSSSSS.....",  // 13 clean jaw
        "......SSSSSSSS......",  // 14 neck
        "..dDDDDDCDDCDDDDDd..",  // 15 thin chain at the collar (two links)
        ".dDDDDDDDDCDDDDDDDd.",  // 16 tiny cross — top
        "dDDDDDDDCCCDDDDDDDDd",  // 17 tiny cross — arms
        "DDDDDDDDDCDDDDDDDDDD",  // 18 tiny cross — foot
        "DDDDDDDDDDDDDDDDDDDD",  // 19
        "DDDDDDDDDDDDDDDDDDDD",  // 20
        "DDDDDDDDDDDDDDDDDDDD",  // 21
        "DDDDDDDDDDDDDDDDDDDD",  // 22
        "dDDDDDDDDDDDDDDDDDDd",  // 23
    ]

    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base
        g[9] = eyesOpen ? "....SSWESSSSWESS...." : "....SSEESSSSEESS...."
        switch mood {
        case .thriving, .happy: g[12] = "....SSSSMMMMSSSS...."  // grin
        case .content, .sleepy, .hungry: g[12] = "....SSSSSMMSSSSS...."
        }
        return g
    }
}

struct PixelBryanView: View {
    let mood: CompanionMood
    var eyesOpen: Bool = true
    var body: some View {
        PixelArtView(rows: PixelBryan.rows(mood: mood, eyesOpen: eyesOpen),
                     palette: PixelBryan.palette)
            .frame(width: 120, height: 144)
            .accessibilityHidden(true)
    }
}

// MARK: - Pixel Panda (the SHARED buddy character)

/// The shared panda Bryan & Victoria keep thriving together. Health-positive: it
/// only ever naps (never dies / never sick). `thriving` adds bamboo to the scene.
enum PandaMood { case thriving, okay, sleepy }

enum PixelPanda {
    static let palette: [Character: Color] = [
        ".": .clear,
        "W": Color(red: 0.96, green: 0.96, blue: 0.93),   // panda white
        "K": Color(red: 0.16, green: 0.15, blue: 0.17),   // panda black
        "E": Color(red: 0.99, green: 0.99, blue: 0.99),   // eye shine
        "P": Color(red: 0.95, green: 0.66, blue: 0.66),   // pink (cheeks)
        "M": Color(red: 0.30, green: 0.20, blue: 0.20),   // mouth
        "B": Color(red: 0.52, green: 0.73, blue: 0.42),   // bamboo (light)
        "b": Color(red: 0.39, green: 0.56, blue: 0.30),   // bamboo (dark)
    ]

    private static let base: [String] = [
        "...KKKK......KKKK...",  // 0  round ears
        "..KKKKKK....KKKKKK..",  // 1
        "..KKKKKK....KKKKKK..",  // 2
        "...WWWWWWWWWWWWWW...",  // 3  head
        "..WWWWWWWWWWWWWWWW..",  // 4
        ".WWWWWWWWWWWWWWWWWW.",  // 5
        ".WWWKKKKWWWWKKKKWWW.",  // 6  eye-patch tops (rounded)
        ".WWWKEKKWWWWKKEKWWW.",  // 7  big dark eyes w/ tiny glint
        ".WWWKKKKWWWWKKKKWWW.",  // 8
        ".WWWWKKWWWWWWKKWWWW.",  // 9  patch bottoms (rounded)
        ".WWWPWWWWKKWWWWPWWW.",  // 10 rosy cheeks + tiny nose
        ".WWWWWWWMWWMWWWWWWW.",  // 11 smile corners (swapped per mood)
        ".WWWWWWWWMMWWWWWWWW.",  // 12 smile bottom
        "..WWWWWWWWWWWWWWWW..",  // 13
        "...WWWWWWWWWWWWWW...",  // 14
        "..KKWWWWWWWWWWWWKK..",  // 15 arms
        ".KKKWWWWWWWWWWWWKKK.",  // 16
        ".KKWWWWWWWWWWWWWWKK.",  // 17
        "..WWWWWWWWWWWWWWWW..",  // 18 belly
        "..WWWWWWWWWWWWWWWW..",  // 19
        "..KKKWWWWWWWWWWKKK..",  // 20 legs
        "...KKKK......KKKK...",  // 21 feet
        "....................",  // 22
        "....................",  // 23
    ]

    static func rows(mood: PandaMood, eyesOpen: Bool = true, chewOpen: Bool = false) -> [String] {
        var g = base
        switch mood {
        case .thriving:
            g[16] = "BKKKWWWWWWWWWWWWKKKB"          // bamboo grows in
            g[17] = "bKKWWWWWWWWWWWWWWKKb"
            g[18] = "B.WWWWWWWWWWWWWWWW.B"
            g[19] = "b.WWWWWWWWWWWWWWWW.b"
        case .okay:
            break                                   // base = big eyes + happy smile
        case .sleepy:
            g[7]  = ".WWWKKKKWWWWKKKKWWW."          // eyes closed (resting), no glint
            g[8]  = ".WWWKKKKWWWWKKKKWWW."
            g[11] = ".WWWWWWWWMMWWWWWWWW."          // small calm mouth
            g[12] = ".WWWWWWWWWWWWWWWWWW."
        }
        // A quick blink — close the eyes (drop the white + glint) for a frame or two. Gives the
        // panda the same "alive" feel as Sprout. (Sleepy already rests with eyes closed.)
        if !eyesOpen && mood != .sleepy {
            g[7] = ".WWWKKKKWWWWKKKKWWW."
            g[8] = ".WWWKKKKWWWWKKKKWWW."
        }
        // Munching the bamboo (thriving only): open the mouth for the "chew" frame so the panda
        // looks like it's happily eating, alternating with the closed smile on a timer.
        if chewOpen && mood == .thriving {
            g[11] = ".WWWWWWWMMMMWWWWWWW."
            g[12] = ".WWWWWWWMMMMWWWWWWW."
        }
        return g
    }
}

struct PixelPandaView: View {
    let mood: PandaMood
    /// Eyes open when true; briefly false during a blink (see `SharedPandaPlaceholder`).
    var eyesOpen: Bool = true
    /// When true (thriving only), the mouth opens for a "chewing the bamboo" frame.
    var chewOpen: Bool = false
    var body: some View {
        PixelArtView(rows: PixelPanda.rows(mood: mood, eyesOpen: eyesOpen, chewOpen: chewOpen),
                     palette: PixelPanda.palette)
            .frame(width: 150, height: 150)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Pixel Victoria — moods") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CompanionMood.allCases, id: \.self) { mood in
                VStack(spacing: 4) {
                    PixelVictoriaView(mood: mood, eyesOpen: mood != .sleepy)
                    Text(mood.label).font(.caption).foregroundStyle(.white)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
#endif
