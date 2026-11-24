import SwiftUI

/// Compatibility layer. The feature screens (built in parallel) used some flat
/// token/type names; these map them onto the canonical APIs so everything compiles
/// without rewriting the otherwise-solid UI code.
extension Theme {
    // Spacing (flat → nested)
    static let spacingXS = Space.xs
    static let spacingS  = Space.sm
    static let spacingM  = Space.md
    static let spacingL  = Space.lg
    static let spacingXL = Space.xl

    // Radius (flat → nested)
    static let radiusS = Radius.sm
    static let radiusM = Radius.md
    static let radiusL = Radius.lg
    static let cornerRadius: CGFloat = Radius.md

    // Color aliases — computed so they follow the active skin (a `static let` would
    // capture the first skin's value and never update on a theme switch).
    // (textPrimary / textSecondary / divider now live in Shared/Theme.swift so both
    // the app and the widget target resolve them.)
    static var accent: Color      { brand }
    static var accentSoft: Color  { brandSoft }
    static var primary: Color     { brand }
    static var primarySoft: Color { brandSoft }

    /// Alias kept for the few call sites that used `Theme.text`.
    static var text: Color { textPrimary }

    // Font aliases (used as functions by some screens)
    static func title() -> Font { .title2.weight(.bold) }
    static func largeTitle() -> Font { .largeTitle.weight(.bold) }
    /// Rounded, monospaced-digit number font at a given size.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension UserProfile {
    /// Friendly display name with a gentle fallback.
    var currentDisplayName: String { name.isEmpty ? "friend" : name }
}

// MARK: - MealType alias used by some feature screens
extension MealType {
    var title: String { label }
}

// MARK: - Open Food Facts result alias + convenience
typealias OFFProduct = OpenFoodFactsService.FoodHit
extension OpenFoodFactsService.FoodHit {
    var caloriesPerServing: Double { calories }
}

// MARK: - Food photo analysis alias + flat accessors
typealias FoodPhotoAnalysis = FoodPhotoAnalyzer.Estimate
extension FoodPhotoAnalyzer.Estimate {
    var totalCalories: Double { total_calories }
    var totalProteinG: Double { total_protein_g }
    var totalCarbsG: Double { total_carbs_g }
    var totalFatG: Double { total_fat_g }
    var caloriesLow: Double { calories_low }
    var caloriesHigh: Double { calories_high }
    /// Per-item assumptions gathered for display.
    var assumptions: [String]? {
        let all = items.map(\.assumptions).filter { !$0.isEmpty }
        return all.isEmpty ? nil : all
    }
}
extension FoodPhotoAnalyzer.Estimate.Item {
    /// A human-readable portion string derived from the estimated grams.
    var quantity: String { "\(Int(estimated_grams)) g" }
}
