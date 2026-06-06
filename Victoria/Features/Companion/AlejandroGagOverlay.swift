import SwiftUI

/// The rival "gag": when Victoria hits her daily fuel goal, her summer-bet rival **Alejandro**
/// pops in (over a dimmed screen), gets pelted by a few tiny bombs, the screen flashes a boom,
/// he flips to a comic dead face (X_X) and **"$200 closer 💸"** + coins float up — then it all
/// fades. Pure celebration overlay; Alejandro is a motivational FIGURE (no data sync). The
/// dashboard shows this once per goal-hit day and it self-dismisses via `onDone`.
struct AlejandroGagOverlay: View {
    var onDone: () -> Void

    @State private var shown = false       // scrim + content scale/opacity in
    @State private var bombsDown = false   // bombs fall onto him
    @State private var boom = false        // explosion flash (replaces bombs)
    @State private var dead = false        // smug → dead face
    @State private var reward = false      // "$200 closer" + coins appear
    @State private var coinsFly = false    // coins drift up + fade
    @State private var leaving = false     // fade everything out

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bombX: [CGFloat] = [-50, 2, 52]
    private let coinX: [CGFloat] = [-46, -2, 48]

    var body: some View {
        // GeometryReader gives an explicit full-screen size so the scrim genuinely covers the
        // whole screen and the content centers (a plain ZStack in an overlay sizes to content).
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(leaving ? 0 : (shown ? 0.42 : 0))

                VStack(spacing: 16) {
                    ZStack {
                        // Alejandro: smug base → comically dead (tilts as he keels over).
                        Image(dead ? "alejandro_dead" : "alejandro_base")
                            .resizable().scaledToFit()
                            .frame(width: 176, height: 196)
                            .rotationEffect(.degrees(dead ? -7 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: dead)

                        // Tiny bombs raining down onto him.
                        if !boom && !dead {
                            ForEach(Array(bombX.enumerated()), id: \.offset) { i, x in
                                Image("bomb")
                                    .resizable().scaledToFit()
                                    .frame(width: 38, height: 38)
                                    .offset(x: x, y: bombsDown ? -20 : -320)
                                    .rotationEffect(.degrees(bombsDown ? 12 : -20))
                                    .opacity(bombsDown ? 1 : 0)
                                    .animation(.easeIn(duration: 0.44).delay(Double(i) * 0.09), value: bombsDown)
                            }
                        }

                        // Explosion flash over him.
                        if boom {
                            Image("boom")
                                .resizable().scaledToFit()
                                .frame(width: 220, height: 220)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }

                        // Coins drifting up from the blast.
                        if reward {
                            ForEach(Array(coinX.enumerated()), id: \.offset) { i, x in
                                Text("💸").font(.title)
                                    .offset(x: x, y: coinsFly ? -70 : 8)
                                    .opacity(coinsFly ? 0 : 1)
                            }
                        }
                    }
                    .frame(height: 200)

                    if reward {
                        Text("$200 closer 💸")
                            .font(.title3.weight(.heavy))
                            .fontDesign(.rounded)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(leaving ? 0 : (shown ? 1 : 0))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: shown)
        .animation(.easeInOut(duration: 0.4), value: leaving)
        .sensoryFeedback(.impact(weight: .heavy), trigger: boom)
        .sensoryFeedback(.success, trigger: reward)
        .allowsHitTesting(false)   // transient — never blocks the dashboard
        .onAppear { run() }
    }

    private func run() {
        #if DEBUG
        // DEBUG: freeze at the payoff (dead + "$200 closer") for a clean screenshot.
        if CommandLine.arguments.contains("--gag-hold") {
            shown = true; dead = true; reward = true
            return
        }
        #endif
        if reduceMotion {
            shown = true; dead = true; reward = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                withAnimation(.easeOut(duration: 0.45)) { leaving = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) { onDone() }
            return
        }
        shown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { bombsDown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.84) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { boom = true }
            dead = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.18) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { reward = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
            withAnimation(.easeOut(duration: 1.2)) { coinsFly = true }
        }
        // Hold on the payoff (dead + "$200 closer") a good while so it lands, then fade. (~5s total.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) {
            withAnimation(.easeOut(duration: 0.45)) { leaving = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.1) { onDone() }
    }
}
