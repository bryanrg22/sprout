import SwiftUI

/// Self-contained pixel-art for the WIDGET target.
///
/// Widgets can't reach the app-only `PixelCompanion`/`CompanionMood` types (those
/// live in the Victoria app target), and a widget never animates — it renders one
/// fixed frame. So this file DUPLICATES, as flat static data, the *thriving* pose
/// of the two characters the app already draws:
///
///   • `WidgetPixelVictoria` — the companion (pixel-Victoria), beaming + eyes open.
///   • `WidgetPixelPanda`    — the shared buddy panda, thriving (smiling + bamboo).
///
/// The grids and palettes are copied verbatim from
/// `Victoria/Features/Companion/PixelCompanion.swift` and frozen to one happy
/// frame. Keeping a copy here (rather than sharing the app type) is the intended
/// trade: the widget stays a leaf with no cross-target dependency. This file lives
/// in `Shared/`, so it compiles in BOTH the app and the widget extension.

// MARK: - Renderer

/// Renders a character grid as crisp pixels with a `Canvas`. Sizes square pixels
/// to fit the available space while preserving the sprite's aspect ratio, and
/// centers the result. (Mirrors the app's `PixelArtView`; kept private to Shared
/// so it never clashes with the app-target type of the same role.)
struct WidgetPixelArtView: View {
    let rows: [String]
    var palette: [Character: Color]

    var body: some View {
        Canvas { ctx, size in
            let cols = rows.map(\.count).max() ?? 0
            let rowCount = rows.count
            guard cols > 0, rowCount > 0 else { return }

            // Largest square pixel that fits, centered.
            let px = min(size.width / CGFloat(cols), size.height / CGFloat(rowCount))
            let originX = (size.width - px * CGFloat(cols)) / 2
            let originY = (size.height - px * CGFloat(rowCount)) / 2

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

// MARK: - Pixel Victoria (frozen "thriving" pose)

/// Fixed copy of the companion (pixel-Victoria) in her happiest pose: eyes open,
/// wide beaming smile. Data copied from `PixelVictoria` (app target) and frozen.
enum WidgetPixelVictoria {
    /// 20 wide × 24 tall. Identical aspect ratio to the app sprite.
    static let aspect: CGFloat = 20.0 / 24.0

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

    /// The base grid with the thriving frame baked in: row 9 = eyes open
    /// (catch-light), row 12 = wide beaming smile.
    static let rows: [String] = [
        ".......HHHHHH.......",  // 0  crown
        ".....HHHHhhHHHH.....",  // 1  center part
        "....HHHHhhhhHHHH....",  // 2
        "...HHHHHHHHHHHHHH...",  // 3
        "..HHHHHHHHHHHHHHHH..",  // 4
        "..HHHHSSSSSSSSHHHH..",  // 5  hairline / forehead
        "..HHHSSSSSSSSSSHHH..",  // 6
        "..HHSSbbSSSSbbSSHH..",  // 7  eyebrows
        "..HHSSSSSSSSSSSSHH..",  // 8  bare face
        "..HHSSWESSSSWESSHH..",  // 9  eyes OPEN (glossy)
        "..HHSSSSSSSSSSSSHH..",  // 10
        "..HHSSCSSSSSSCSSHH..",  // 11 cheeks
        "..HHSSSSMMMMSSSSHH..",  // 12 wide beaming smile
        "...HHSSSSSSSSSSHH...",  // 13 chin
        "...HHHHSSSSSSHHHH...",  // 14 neck
        "..HHHTTTTTTTTTTHHH..",  // 15 shoulders
        "..HHTTTTTNNTTTTTHH..",  // 16 collar + necklace
        ".HHhTTTTTTTTTTTThHH.",  // 17 long hair past shoulders
        ".HHHTTTTTTTTTTTTHHH.",  // 18
        ".HHhTTTTTTTTTTTThHH.",  // 19
        "..HHHTTTTTTTTTTHHH..",  // 20 hair tapering
        "...HHHTTTTTTTTHHH...",  // 21
        "...HHH........HHH...",  // 22 long hair tips
        "....HH........HH....",  // 23
    ]
}

/// Frozen pixel-Victoria for widgets. Aspect-locked so she's never stretched.
struct WidgetPixelVictoriaView: View {
    var body: some View {
        WidgetPixelArtView(rows: WidgetPixelVictoria.rows,
                           palette: WidgetPixelVictoria.palette)
            .aspectRatio(WidgetPixelVictoria.aspect, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

// MARK: - Pixel Bryan (frozen "thriving" pose)

/// Fixed copy of Bryan's companion in his thriving pose: eyes open (catch-light),
/// grin. Shown when the profile's `companionAvatar` is `.bryan` (the Cool skin user).
/// Data copied from `PixelBryan` (app target) and frozen to one happy frame, so the
/// widget never reaches the app-only type. Reads on the near-black Cool canvas.
enum WidgetPixelBryan {
    /// 20 wide × 24 tall. Same aspect ratio as Victoria so the layout is unchanged.
    static let aspect: CGFloat = 20.0 / 24.0

    static let palette: [Character: Color] = [
        ".": .clear,
        "H": Color(red: 0.20, green: 0.14, blue: 0.10),   // hair (dark brown)
        "h": Color(red: 0.37, green: 0.27, blue: 0.18),   // hair curl highlight (warm)
        "S": Color(red: 0.80, green: 0.57, blue: 0.41),   // skin (warm tan)
        "K": Color(red: 0.66, green: 0.45, blue: 0.31),   // skin shadow / jaw
        "E": Color(red: 0.12, green: 0.09, blue: 0.08),   // eyes
        "W": Color(red: 0.98, green: 0.98, blue: 0.99),   // eye catch-light
        "b": Color(red: 0.11, green: 0.10, blue: 0.11),   // thick brow
        "F": Color(red: 0.16, green: 0.13, blue: 0.12),   // facial hair (mustache)
        "M": Color(red: 0.50, green: 0.24, blue: 0.22),   // mouth
        "D": Color(red: 0.21, green: 0.21, blue: 0.24),   // dark tee
        "d": Color(red: 0.13, green: 0.13, blue: 0.16),   // tee shadow
        "C": Color(red: 0.88, green: 0.89, blue: 0.93),   // silver Cuban chain + cross
        "P": Color(red: 0.33, green: 0.22, blue: 0.14),   // brown scapular (escapulario)
    ]

    /// Base grid with the thriving frame baked in: row 9 = eyes open (catch-light),
    /// row 12 = grin. (Copied verbatim from `PixelBryan.base` + `.thriving`.)
    static let rows: [String] = [
        "....HHhHHHHHhH......",  // 0  curly top (warm curl shine)
        "..HHhHHHHHhHHHHH....",  // 1  voluminous + texture
        ".HHHHHHHHHHHHHHHHH..",  // 2  widest, fluffy
        ".HHhHHHHHHHHHhHHHH..",  // 3  curl texture
        ".HHHHHHHHHHHHHHHHHH.",  // 4
        "..HHHHSSSSSSSSHHHH..",  // 5  hairline / forehead
        "...HSSSSSSSSSSSSH...",  // 6  tapered / faded sides
        "...HSSbbSSSSbbSSH...",  // 7  eyebrows
        "....SSSSSSSSSSSS....",  // 8  faded sides → skin
        "....SSWESSSSWESS....",  // 9  eyes OPEN (glossy)
        "....SSSSSSSSSSSS....",  // 10
        "....SSSSFFFFSSSS....",  // 11 mustache
        "....SSSSMMMMSSSS....",  // 12 grin (thriving)
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
}

/// Frozen thriving pixel-Bryan for widgets. Aspect-locked so he's never stretched.
struct WidgetPixelBryanView: View {
    var body: some View {
        WidgetPixelArtView(rows: WidgetPixelBryan.rows,
                           palette: WidgetPixelBryan.palette)
            .aspectRatio(WidgetPixelBryan.aspect, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

// MARK: - Pixel Panda (frozen "thriving" pose)

/// Fixed copy of the shared buddy panda in its thriving pose: open eyes, happy
/// smile, bamboo growing in. Data copied from `PixelPanda` (app target) and frozen.
enum WidgetPixelPanda {
    /// 20 wide × 24 tall.
    static let aspect: CGFloat = 20.0 / 24.0

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

    /// The base grid with the thriving frame baked in: row 11 = happy open smile,
    /// rows 16–19 = bamboo grows in at the sides.
    static let rows: [String] = [
        "...KKK........KKK...",  // 0  round ears
        "..KKKKK......KKKKK..",  // 1
        "..KKKKK......KKKKK..",  // 2
        "...WWWWWWWWWWWWWW...",  // 3  head
        "..WWWWWWWWWWWWWWWW..",  // 4
        ".WWWWWWWWWWWWWWWWWW.",  // 5
        ".WWKKKKKWWWWKKKKKWW.",  // 6  eye-patch tops
        ".WWKEEEKWWWWKEEEKWW.",  // 7  big eyes (white)
        ".WWKEKEKWWWWKEKEKWW.",  // 8  eyes (pupil) — open
        ".WWKKKKKWWWWKKKKKWW.",  // 9  patch bottoms
        ".WWWPWWWKKWWWWWPWWWW",  // 10 rosy cheeks + tiny nose
        ".WWWWWWMMMMWWWWWWWW.",  // 11 happy open smile (thriving)
        ".WWWWWWWWWWWWWWWWWW.",  // 12
        "..WWWWWWWWWWWWWWWW..",  // 13
        "...WWWWWWWWWWWWWW...",  // 14
        "..KKWWWWWWWWWWWWKK..",  // 15 arms
        "BKKKWWWWWWWWWWWWKKKB",  // 16 bamboo grows in
        "bKKWWWWWWWWWWWWWWKKb",  // 17
        "B.WWWWWWWWWWWWWWWW.B",  // 18
        "b.WWWWWWWWWWWWWWWW.b",  // 19
        "..KKKWWWWWWWWWWKKK..",  // 20 legs
        "...KKKK......KKKK...",  // 21 feet
        "....................",  // 22
        "....................",  // 23
    ]
}

/// Frozen thriving panda for widgets. Aspect-locked so it's never stretched.
struct WidgetPixelPandaView: View {
    var body: some View {
        WidgetPixelArtView(rows: WidgetPixelPanda.rows,
                           palette: WidgetPixelPanda.palette)
            .aspectRatio(WidgetPixelPanda.aspect, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

// MARK: - Custom character (the person's own, from `WidgetAvatarFile`)

/// The custom character's widget copy, drawn with hard pixel edges like the grids above.
/// One image for every mood (version 1 makes a single image per person).
struct WidgetCustomAvatarView: View {
    let png: Data

    var body: some View {
        if let image = UIImage(data: png) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            WidgetNeutralCompanionView()
        }
    }
}

/// Drawn in the companion's place when there is no character this widget may show: the
/// custom image is missing or belongs to another profile. The app's own mark, in the
/// user's skin; it says nothing about anyone.
struct WidgetNeutralCompanionView: View {
    var body: some View {
        Image(systemName: "leaf.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Theme.textSecondary)
            .padding(8)
            .accessibilityHidden(true)
    }
}
