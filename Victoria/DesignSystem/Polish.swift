import SwiftUI

/// Shared visual-polish helpers layered on top of the base Theme.
extension View {
    /// An elevated card: continuous rounded rect + soft shadow for gentle depth.
    func cardElevated(padding: CGFloat = Theme.Space.md, radius: CGFloat = Theme.Radius.lg) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }

    func softShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

/// A gradient progress ring with a rounded cap — the dashboard hero.
struct GradientRing: View {
    var progress: Double            // 0...1+
    var lineWidth: CGFloat = 16
    var gradient: AngularGradient
    var track: Color = Color(.tertiarySystemFill)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
    }
}

extension AngularGradient {
    /// Coral brand sweep for the calories ring.
    static var brandSweep: AngularGradient {
        AngularGradient(colors: [Theme.brand, Theme.brandDeep, Theme.brand],
                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }
}

/// A speedometer-style gauge for the calories hero: a 270° arc with the opening at the
/// bottom (like a car dash), an always-visible soft track, a gradient progress sweep, evenly
/// spaced tick marks, and a short pointer that swings to the current value. It replaces the
/// full ring, which vanished at 0% on the light theme (its faint track + an empty arc left
/// just a bare number). The caller supplies the centered readout via the trailing closure.
///
/// Geometry: a `Circle` trimmed to 3/4 of a turn (270°) and rotated 135° so the 90° gap sits
/// at the bottom. Ticks + pointer use the clock-hand recipe (`.offset` then `.rotationEffect`,
/// which pivots about the gauge center because `.offset` doesn't change the layout frame).
struct CalorieSpeedometer<Center: View>: View {
    var progress: Double                 // 0...1+ (clamped for display)
    var gradient: AngularGradient
    var size: CGFloat = 150
    var lineWidth: CGFloat = 13
    var track: Color = Theme.divider
    /// Optional "in range" zone (as fractions of the full scale) drawn as a soft band on the
    /// track — e.g. ~0.9...1.0 marks where her healthy calorie range sits on the gauge.
    var rangeBand: ClosedRange<Double>? = nil
    var rangeColor: Color = Theme.info

    @ViewBuilder var center: () -> Center

    /// 270° as a fraction of a full turn; `baseRotation` drops the 90° gap to the bottom.
    private let sweep = 0.75
    private let baseRotation = 135.0
    private var p: Double { min(max(progress, 0), 1) }

    /// Screen angle (deg) for a fill fraction `f` along the arc: 0 = empty (lower-left),
    /// 0.5 = top, 1 = full (lower-right). Matches a pointer drawn pointing up at f = 0.5.
    private func angle(_ f: Double) -> Double { (f - 0.5) * 270 }

    var body: some View {
        ZStack {
            // Always-visible track (themed, so it shows on both the light and dark skins).
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(baseRotation))

            // Tick marks every 1/8 of the arc — the dial's "speedometer" character. Majors
            // (the ends + quarters) are longer + darker so the dial reads clearly.
            ForEach(0..<9) { i in
                Capsule()
                    .fill(Theme.textSecondary.opacity(i % 2 == 0 ? 0.42 : 0.22))
                    .frame(width: 2, height: i % 2 == 0 ? 9 : 5)
                    .offset(y: -(size / 2 - lineWidth - 7))
                    .rotationEffect(.degrees(angle(Double(i) / 8)))
            }

            // The healthy "in range" zone — a soft band on the track so she can see where to aim
            // (the gauge spans to the ceiling; this marks floor→ceiling).
            if let band = rangeBand {
                Circle()
                    .trim(from: sweep * min(max(band.lowerBound, 0), 1),
                          to: sweep * min(max(band.upperBound, 0), 1))
                    .stroke(rangeColor.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(baseRotation))
            }

            // Gradient progress sweep, growing from the empty (lower-left) end. A round cap
            // leaves a soft "drop" at the leading edge that marks where today sits.
            Circle()
                .trim(from: 0, to: sweep * p)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(baseRotation))
                .shadow(color: Theme.brand.opacity(0.28), radius: 6)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: p)

            center()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Count-up number

/// A number that animates from 0 up to `value` on appear (and re-animates when
/// `value` changes), like Apple Fitness. Uses SwiftUI's `animation(value:)` +
/// a custom `AnimatableModifier` so it ticks through intermediate values.
struct CountUpText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    /// Set by the parent to drive the 0→value reveal.
    var isActive: Bool

    private var displayed: Double

    init(value: Double, isActive: Bool, format: @escaping (Double) -> String) {
        self.value = value
        self.isActive = isActive
        self.format = format
        self.displayed = isActive ? value : 0
    }

    var animatableData: Double {
        get { displayed }
        set { displayed = newValue }
    }

    var body: some View {
        Text(format(displayed))
    }
}

// MARK: - Staggered entrance

/// Fades + lifts a view into place, with an optional delay so a stack of cards
/// can cascade in. Drive with a single `appeared` flag flipped in `.onAppear`.
struct AppearLift: ViewModifier {
    let appeared: Bool
    var delay: Double = 0
    var distance: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : distance)
            .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay), value: appeared)
    }
}

extension View {
    /// Cascade this view in. `index` controls the stagger order.
    func appearLift(_ appeared: Bool, index: Int = 0, step: Double = 0.07) -> some View {
        modifier(AppearLift(appeared: appeared, delay: Double(index) * step))
    }
}
