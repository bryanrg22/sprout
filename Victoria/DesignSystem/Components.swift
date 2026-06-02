import SwiftUI

/// A circular progress ring (used for calories + macros).
struct ProgressRing: View {
    var progress: Double            // 0...1 (can exceed for "over")
    var lineWidth: CGFloat = 12
    var color: Color
    var track: Color = Color(.tertiarySystemFill)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
    }
}

/// A labeled horizontal macro bar.
struct MacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color
    var unit: String = "g"

    private var progress: Double { target > 0 ? value / target : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded())) \(unit)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(color)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

/// A compact stat tile for the dashboard grid.
struct StatTile<Trailing: View>: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, value: String, systemImage: String, tint: Color,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title; self.value = value; self.systemImage = systemImage
        self.tint = tint; self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(tint)
                Spacer()
                trailing()
            }
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Primary call-to-action button style.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.brandGradient)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Small confidence badge for AI estimates.
struct ConfidenceBadge: View {
    var confidence: EstimateConfidence
    private var color: Color {
        switch confidence { case .high: return Theme.positive; case .medium: return Theme.warning; case .low: return .secondary }
    }
    var body: some View {
        Text(confidence.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Section header with optional action.
struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title).font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
