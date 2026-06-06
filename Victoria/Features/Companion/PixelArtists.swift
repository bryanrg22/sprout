import SwiftUI

// Hand-authored pixel-art of artists Bryan likes — a growing roster (exact in-app use TBD:
// collectible companions / cameo Easter eggs / buddy-page guests). Same 20×24 grid + `PixelArtView`
// renderer + `CompanionMood`/blink machinery as `PixelVictoria` / `PixelBryan`, so they animate the
// same way. Reference photos live in `docs/pixel-art-refs/`.

// MARK: - Peso Pluma

/// Short dark textured crop with a tight fade, thick brows, his signature freckles, a slim face,
/// and a black adidas track jacket with white stripes.
enum PixelPeso {
    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.17, green: 0.12, blue: 0.09),   // hair (near-black brown)
        "h": Color(red: 0.29, green: 0.21, blue: 0.14),   // hair texture highlight
        "S": Color(red: 0.83, green: 0.63, blue: 0.48),   // skin (warm)
        "K": Color(red: 0.71, green: 0.51, blue: 0.37),   // skin shadow / slim jaw
        "E": Color(red: 0.12, green: 0.09, blue: 0.08),   // eyes
        "W": Color(red: 0.98, green: 0.98, blue: 0.99),   // eye catch-light
        "b": Color(red: 0.11, green: 0.08, blue: 0.06),   // thick brow
        "f": Color(red: 0.73, green: 0.51, blue: 0.39),   // freckles
        "M": Color(red: 0.55, green: 0.28, blue: 0.26),   // mouth
        "D": Color(red: 0.13, green: 0.13, blue: 0.15),   // black track jacket
        "d": Color(red: 0.08, green: 0.08, blue: 0.10),   // jacket shadow
        "Z": Color(red: 0.93, green: 0.93, blue: 0.95),   // white adidas stripes
    ]

    private static let base: [String] = [
        ".....HHHHHHHH.......",  // 0  textured top
        "...HHHHHHHHHHHHH....",  // 1
        "..HHHHHHHHHHHHHHH...",  // 2
        "..HHHhHHHHHHhHHHH...",  // 3  texture
        "..HHHHHHHHHHHHHHH...",  // 4
        "..HHHSSSSSSSSSHHH...",  // 5  hairline
        "..HhSSSSSSSSSSShH...",  // 6  faded short sides
        "...SSbbSSSSbbSSS....",  // 7  thick brows
        "...SSSSSSSSSSSSS....",  // 8
        "...SSWESSSSWESSS....",  // 9  eyes (swapped per blink)
        "...SSfSSSSSSfSSS....",  // 10 freckles
        "...SSSfSSSSfSSSS....",  // 11 freckles
        "....SSSSMMSSSSS.....",  // 12 mouth (swapped per mood)
        "....KSSSSSSSSK......",  // 13 slim jaw
        ".....SSSSSSSS.......",  // 14 neck
        "...DDDDDDDDDDDDDD...",  // 15 jacket collar
        "..DDDZZDDDDDDZZDDD..",  // 16 white stripes down the sleeves
        ".DDDDZZDDDDDDZZDDDD.",  // 17
        "DDDDDZZDDDDDDZZDDDDD",  // 18
        "DDDDDZZDDDDDDZZDDDDD",  // 19
        "DDDDDZZDDDDDDZZDDDDD",  // 20
        "DDDDDDDDDDDDDDDDDDDD",  // 21
        "DDDDDDDDDDDDDDDDDDDD",  // 22
        "dDDDDDDDDDDDDDDDDDDd",  // 23
    ]

    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base
        g[9] = eyesOpen ? "...SSWESSSSWESSS...." : "...SSEESSSSEESSS...."
        switch mood {
        case .thriving, .happy:            g[12] = "....SSSMMMMSSSS....."
        case .content, .sleepy, .hungry:   g[12] = "....SSSSMMSSSSS....."
        }
        return g
    }
}

struct PixelPesoView: View {
    let mood: CompanionMood
    var eyesOpen: Bool = true
    var body: some View {
        PixelArtView(rows: PixelPeso.rows(mood: mood, eyesOpen: eyesOpen), palette: PixelPeso.palette)
            .frame(width: 120, height: 144)
            .accessibilityHidden(true)
    }
}

// MARK: - Tito Doble P

/// Wavy side-swept dark-brown hair, his signature thin gold wire glasses, a light beard along the
/// jaw, thick brows, and a black quarter-zip with a visible zipper pull.
enum PixelTito {
    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.18, green: 0.13, blue: 0.10),   // hair (dark brown)
        "h": Color(red: 0.32, green: 0.24, blue: 0.17),   // hair wave highlight
        "S": Color(red: 0.82, green: 0.62, blue: 0.46),   // skin (warm)
        "K": Color(red: 0.74, green: 0.54, blue: 0.40),   // skin shadow
        "E": Color(red: 0.12, green: 0.09, blue: 0.08),   // eyes
        "W": Color(red: 0.98, green: 0.98, blue: 0.99),   // eye catch-light
        "b": Color(red: 0.22, green: 0.15, blue: 0.11),   // thick brow
        "F": Color(red: 0.62, green: 0.47, blue: 0.36),   // light beard / stubble
        "M": Color(red: 0.52, green: 0.28, blue: 0.26),   // mouth
        "G": Color(red: 0.86, green: 0.80, blue: 0.58),   // thin gold glasses frame
        "D": Color(red: 0.13, green: 0.13, blue: 0.15),   // black quarter-zip
        "d": Color(red: 0.08, green: 0.08, blue: 0.10),   // top shadow
        "z": Color(red: 0.48, green: 0.48, blue: 0.51),   // zipper pull
    ]

    private static let base: [String] = [
        ".....HHHHHHHH.......",  // 0  wavy top
        "...HHHHHHHHHHHHH....",  // 1
        "..HHhhHHHHHHHHHHHH..",  // 2  swept highlight strand
        ".HHHhhHHHHHHHHHHHH..",  // 3
        ".HHHHhHHHHHHHHHHHHH.",  // 4
        ".HHHHHHSSSSSSHHHHHH.",  // 5  hairline
        "..HHSSSSSSSSSSSHHHH.",  // 6  tapered sides
        "..HSSbbSSSSSbbSSSH..",  // 7  thick brows
        "..GGGGGGSSGGGGGGGH..",  // 8  glasses top rim (+ bridge gap)
        "..GSWEGSSSGSWEGSSH..",  // 9  eyes inside the lenses (swapped per blink)
        "..GGGGGGSSGGGGGGSS..",  // 10 glasses bottom rim
        "...SSSSSSSSSSSSSSS..",  // 11 cheeks
        "...SSSSSSFFSSSSSSS..",  // 12 light mustache
        "...SFSSMMMMSSSSFSS..",  // 13 mouth (swapped per mood) + jaw beard
        "...SFFSSSSSSSSFFSS..",  // 14 beard along the jaw
        "....SFFFFFFFFFS.....",  // 15 chin beard
        "..dDDDDDDzDDDDDDd...",  // 16 collar + zipper
        ".dDDDDDDDzDDDDDDDd..",  // 17
        "dDDDDDDDDzDDDDDDDDd.",  // 18
        "DDDDDDDDDzDDDDDDDDD.",  // 19 zip pull tail
        "DDDDDDDDDDDDDDDDDDDD",  // 20
        "DDDDDDDDDDDDDDDDDDDD",  // 21
        "DDDDDDDDDDDDDDDDDDDD",  // 22
        "dDDDDDDDDDDDDDDDDDDd",  // 23
    ]

    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base
        g[9] = eyesOpen ? "..GSWEGSSSGSWEGSSH.." : "..GSEEGSSSGSEEGSSH.."
        switch mood {
        case .thriving, .happy:            g[13] = "...SFSSMMMMSSSSFSS.."
        case .content, .sleepy, .hungry:   g[13] = "...SFSSSMMSSSSSFSS.."
        }
        return g
    }
}

struct PixelTitoView: View {
    let mood: CompanionMood
    var eyesOpen: Bool = true
    var body: some View {
        PixelArtView(rows: PixelTito.rows(mood: mood, eyesOpen: eyesOpen), palette: PixelTito.palette)
            .frame(width: 120, height: 144)
            .accessibilityHidden(true)
    }
}

// MARK: - JOP (Fuerza Regida)

/// Hair slicked straight back (wet-comb strands) off a fully exposed high forehead, dark length down
/// both outer sides, a mustache + goatee circle-beard with a visible mouth, a diamond stud earring,
/// thick brows, and his cream knit V-neck sweater. (His slicked-back-with-length signature.)
enum PixelJOP {
    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.11,  green: 0.085, blue: 0.075), // slicked hair (darkest)
        "h": Color(red: 0.38,  green: 0.29,  blue: 0.21),  // wet-comb highlight strand
        "k": Color(red: 0.20,  green: 0.15,  blue: 0.12),  // hair edge / shadow
        "S": Color(red: 0.83,  green: 0.61,  blue: 0.45),  // skin
        "s": Color(red: 0.71,  green: 0.50,  blue: 0.36),  // skin shadow
        "E": Color(red: 0.10,  green: 0.08,  blue: 0.07),  // brows / eye line
        "W": Color(red: 0.99,  green: 0.99,  blue: 1.00),  // eye white + diamond stud sparkle
        "F": Color(red: 0.15,  green: 0.11,  blue: 0.09),  // mustache + goatee
        "M": Color(red: 0.50,  green: 0.27,  blue: 0.25),  // lips / open mouth
        "C": Color(red: 0.96,  green: 0.94,  blue: 0.89),  // cream sweater
        "G": Color(red: 0.66,  green: 0.63,  blue: 0.58),  // sweater outline + V-neck
    ]
    private static let base: [String] = [
        ".....HHHHHHHHHH.....",
        "....HHhhhhhhhhHHH...",
        "...HHHHHHHHHHHHkHH..",
        "...HHhhhhhhhhHHHkH..",
        "..HkHHHHHHHHHHHHkH..",
        "..HkSSSSSSSSSSSSkH..",
        ".HkSSSSSSSSSSSSSSkH.",
        ".HHSSSSSSSSSSSSSSHH.",
        ".HHSSEEsSSSSsEESSHH.",
        ".HHSSEWESSSSEWESSHH.",
        ".HHSSSsSSSSSSsSSSHH.",
        ".WkSSSSSSssSSSSSSkH.",
        ".HkSSSFFFFFFFFSSSkH.",
        ".HkSSSSMMMMMMSSSSkH.",
        ".HkSSSFFFFFFFFSSSkH.",
        ".HkkSSSFFFFFFSSSkkH.",
        "..HhSSSSFFFFSSSShH..",
        "..HHhsSSSSSSSSshHH..",
        "...HhssSSSSSSsshH...",
        "....GsSCCCCCCSsG....",
        "...GCCCCGGCCCCCCG...",
        "..GCCCCCGGCCCCCCCG..",
        "..GCCCCCGGCCCCCCCG..",
        "..GCCCCCGGCCCCCCCG..",
    ]
    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base
        g[9] = eyesOpen ? ".HHSSEWESSSSEWESSHH." : ".HHSSEEESSSSEEESSHH."
        switch mood {
        case .thriving, .happy:   g[13] = ".HkSSSMMMMMMMMSSSkH."   // wide grin
        case .content, .hungry:   g[13] = ".HkSSSSMMMMMMSSSSkH."   // neutral
        case .sleepy:             g[13] = ".HkSSSSSMMMMSSSSSkH."   // small, relaxed
        }
        return g
    }
}

struct PixelJOPView: View {
    let mood: CompanionMood
    var eyesOpen: Bool = true
    var body: some View {
        PixelArtView(rows: PixelJOP.rows(mood: mood, eyesOpen: eyesOpen), palette: PixelJOP.palette)
            .frame(width: 120, height: 144)
            .accessibilityHidden(true)
    }
}

// MARK: - Chuyin (the Fuerza Regida mascot)

/// The big-headed FR mascot: a round cream/oatmeal knit ball-head, a Burberry-pattern beanie (knit
/// base + black/white vertical stripes + the signature red band + a top-knot), huge round shiny
/// black eyes, thick angled brows, a wide toothy grin, little ears, and a black puffer + silver chain.
enum PixelChuyin {
    static let palette: [Character: Color] = [
        ".": .clear,
        "C": Color(red: 0.80, green: 0.73, blue: 0.62),  // tan clay head
        "c": Color(red: 0.64, green: 0.57, blue: 0.47),  // head shadow / outline / ears
        "T": Color(red: 0.86, green: 0.80, blue: 0.70),  // beanie knit (lighter tan)
        "t": Color(red: 0.70, green: 0.64, blue: 0.54),  // beanie shadow
        "K": Color(red: 0.11, green: 0.10, blue: 0.09),  // black: beanie stripes, eyes, brows
        "Z": Color(red: 0.99, green: 0.99, blue: 0.98),  // white eye-shine
        "R": Color(red: 0.80, green: 0.18, blue: 0.16),  // red beanie band + R pendant
        "P": Color(red: 0.93, green: 0.68, blue: 0.64),  // pink lips
        "W": Color(red: 0.84, green: 0.83, blue: 0.81),  // teeth (grey-white)
        "M": Color(red: 0.28, green: 0.15, blue: 0.15),  // dark mouth opening
        "D": Color(red: 0.13, green: 0.13, blue: 0.15),  // black puffer jacket
        "d": Color(red: 0.07, green: 0.07, blue: 0.09),  // jacket deep shadow
        "G": Color(red: 0.85, green: 0.87, blue: 0.91),  // silver Cuban chain (highlight)
        "g": Color(red: 0.55, green: 0.57, blue: 0.63),  // chain shadow
    ]

    // 20 wide x 24 tall. Knit beanie (0-7), round tan ball-head (8-20), jacket + chain (21-23).
    private static let base: [String] = [
        "........tTTt........",   // 0  knit top-knot / pom
        "......ttTTTTtt......",   // 1  pom base
        ".....tTTTTTTTTt.....",   // 2  dome
        "....tTTKTTTTKTTt....",   // 3  dome + 2 black stripes
        "...tTTTKTTTTKTTTt...",   // 4
        "..RRRRRRRRRRRRRRRR..",   // 5  signature red band
        ".tTTTTTTTTTTTTTTTTt.",   // 6  folded brim — wraps + overhangs
        ".tTTTTTTTTTTTTTTTTt.",   // 7
        "..cCCCCCCCCCCCCCCc..",   // 8  forehead
        "..cCCKKKCCCCKKKCCc..",   // 9  brows
        "..cCCCCCCCCCCCCCCc..",   // 10 gap
        "..cCCKKKCCCCKKKCCc..",   // 11 eye tops
        ".CcCCZKKCCCCZKKCCcC.",   // 12 big glossy eyes + shine (ears poke out l/r)
        ".CcCCKKKCCCCKKKCCcC.",   // 13 eyes (+ ears)
        "..cCCKKKCCCCKKKCCc..",   // 14 eye bottoms
        "..cCCCCCCCCCCCCCCc..",   // 15 cheeks
        "...cCCCCCCCCCCCCc...",   // 16 lower face
        "......cPPPPc........",   // 17 pink top lip
        ".....cPWWWWPc.......",   // 18 teeth
        "......cPMMPc........",   // 19 small open mouth
        "....cCCCCCCCCCCc....",   // 20 chin
        "...dGGGGGGGGGGGGd...",   // 21 silver Cuban chain
        "..dDDDDGgZgZgGDDDDd.",   // 22 jacket + chain links
        ".dDDDDDDGgRgGDDDDDDd",   // 23 black puffer + diamond "R" pendant
    ]

    static func rows(mood: CompanionMood, eyesOpen: Bool) -> [String] {
        var g = base
        if !eyesOpen {
            // Happy blink — eyes flatten to gentle lines.
            g[11] = "..cCCCCCCCCCCCCCCc.."
            g[12] = ".CcCCKKKCCCCKKKCCcC."
            g[13] = "..cCCCKCCCCCCKCCCc.."
            g[14] = "..cCCCCCCCCCCCCCCc.."
        }
        switch mood {
        case .thriving, .happy:
            break   // base = the open pink smile
        case .content, .sleepy, .hungry:
            g[17] = "......cCCCCc........"
            g[18] = "......cPWWPc........"
            g[19] = "......cPPPPc........"
        }
        return g
    }
}

struct PixelChuyinView: View {
    let mood: CompanionMood
    var eyesOpen: Bool = true
    var body: some View {
        PixelArtView(rows: PixelChuyin.rows(mood: mood, eyesOpen: eyesOpen), palette: PixelChuyin.palette)
            .frame(width: 120, height: 144)
            .accessibilityHidden(true)
    }
}

// MARK: - Debug gallery (verify the roster renders; not in the shipping UI)

/// A simple side-by-side of every pixel character, for eyeballing new sprites. Reached with the
/// `--pixel-gallery` launch argument (see `VictoriaApp`). DEBUG-only.
struct PixelGalleryView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Pixel roster").font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    labeled("Victoria") { PixelVictoriaView(mood: .happy) }
                    labeled("Bryan")    { PixelBryanView(mood: .happy) }
                }
                HStack(spacing: 8) {
                    labeled("Peso Pluma")  { PixelPesoView(mood: .happy) }
                    labeled("Tito Doble P"){ PixelTitoView(mood: .happy) }
                }
                HStack(spacing: 8) {
                    labeled("JOP") { PixelJOPView(mood: .happy) }
                    labeled("Chuyin") { PixelChuyinView(mood: .happy) }
                }
            }
            .padding()
        }
    }

    private func labeled<V: View>(_ name: String, @ViewBuilder _ art: () -> V) -> some View {
        VStack(spacing: 6) {
            art()
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

#Preview("Pixel roster") { PixelGalleryView() }
