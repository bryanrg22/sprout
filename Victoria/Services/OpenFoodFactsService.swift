import Foundation

/// Free, keyless nutrition lookup via Open Food Facts (barcode + text search).
///
/// Returns macros, and the label nutrients the product lists, **per serving**. When the
/// product only publishes per-100 g values
/// we compute the per-serving figure from the declared serving weight, so a 414 ml
/// bottle isn't logged as if it were 100 ml. Every result is run through
/// `NutritionSanity` so an obviously-broken community entry is flagged, not trusted.
struct OpenFoodFactsService {

    struct FoodHit: Identifiable {
        let id = UUID()
        var name: String
        var brand: String?
        /// What one logged unit represents, e.g. "1 bottle (414 ml)" or "100 g".
        var servingDescription: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var barcode: String?
        /// True when the looked-up numbers failed a basic plausibility check.
        var isSuspicious: Bool = false
        /// A short note explaining the suspicion (nil when the numbers look fine).
        var sanityNote: String? = nil
        /// The label nutrients the product states, per serving on the same basis as the
        /// macros. One the product does not list stays nil (not known), never 0.
        var detail: NutrientDetail = NutrientDetail()
        /// True when the product lists salt but no sodium, so `detail.sodiumMg` was worked
        /// out from the salt figure (sodium = salt ÷ 2.5).
        var sodiumFromSalt: Bool = false

        /// Said on the confirm sheet when sodium is a conversion rather than a listed value.
        var sodiumNote: String? {
            sodiumFromSalt ? "Sodium worked out from the listed salt (salt ÷ 2.5)." : nil
        }
    }

    /// Salt is sodium chloride; by weight it is 2.5 times its sodium (the factor EU labelling
    /// uses, and the one Open Food Facts itself applies between its `salt` and `sodium` keys).
    static let saltPerSodium = 2.5

    /// The `nutriments` key stem for each label nutrient. Every `_serving` / `_100g` value
    /// under these is in GRAMS whatever the label's unit (`docs/nutrition-detail.md` section 3).
    static let detailKeys: [Nutrient: String] = [
        .saturatedFat: "saturated-fat", .transFat: "trans-fat", .cholesterol: "cholesterol",
        .sodium: "sodium", .fiber: "fiber", .sugars: "sugars", .addedSugars: "added-sugars",
        .vitaminD: "vitamin-d", .calcium: "calcium", .iron: "iron", .potassium: "potassium",
    ]

    /// Open Food Facts asks every client to identify itself with a name, a version and a
    /// way to reach the developer. The contact is the project page, not a personal address:
    /// this string is in a public repository and is sent with every lookup.
    static let userAgent = "Sprout/2.1 (iOS; +https://github.com/bryanrg22/sprout)"
    private static let fields = "product_name,brands,serving_size,serving_quantity,nutriments,code"

    static func product(barcode: String) async throws -> FoodHit? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")!
        let json = try await fetch(url)
        guard (json["status"] as? Int) == 1, let p = json["product"] as? [String: Any] else { return nil }
        return parse(product: p, barcode: barcode)
    }

    static func search(query: String) async throws -> [FoodHit] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=20&fields=\(fields)")!
        let json = try await fetch(url)
        let products = (json["products"] as? [[String: Any]]) ?? []
        return products.compactMap { p in
            let h = parse(product: p, barcode: p["code"] as? String)
            return h.name.isEmpty ? nil : h
        }
    }

    // MARK: - Parsing

    /// Turns one Open Food Facts product dictionary into a per-serving `FoodHit`.
    /// `internal` (not private) so unit tests can exercise it against real-shaped data.
    static func parse(product p: [String: Any], barcode: String?) -> FoodHit {
        let n = (p["nutriments"] as? [String: Any]) ?? [:]

        func num(_ dict: [String: Any], _ key: String) -> Double? {
            if let d = dict[key] as? Double { return d }
            if let s = dict[key] as? String, let d = Double(s) { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return nil
        }

        // Serving weight (g/ml) when declared — lets us scale per-100 g data correctly.
        let servingQty = num(p, "serving_quantity")

        /// Per-serving value for one nutrient: prefer the explicit `_serving`; else
        /// scale `_100g` by the serving weight; else fall back to the per-100 g number.
        /// Crucially each nutrient resolves INDEPENDENTLY, so a single missing
        /// `_serving` field can't drag one macro to 0 while the others are per-serving.
        func perServing(_ servingKey: String, _ per100Keys: [String]) -> Double {
            if let v = num(n, servingKey) { return v }
            guard let per100 = per100Keys.lazy.compactMap({ num(n, $0) }).first else { return 0 }
            if let q = servingQty, q > 0 { return per100 * q / 100.0 }
            return per100
        }

        /// The same resolution for a nutrient that may simply not be listed: `nil` when the
        /// product has neither a `_serving` nor a `_100g` value for it. In grams.
        func perServingIfListed(_ stem: String) -> Double? {
            if let v = num(n, stem + "_serving") { return v }
            guard let per100 = num(n, stem + "_100g") else { return nil }
            if let q = servingQty, q > 0 { return per100 * q / 100.0 }
            return per100
        }

        var detail = NutrientDetail()
        var sodiumFromSalt = false
        for nutrient in Nutrient.allCases {
            guard let stem = Self.detailKeys[nutrient] else { continue }
            var grams = perServingIfListed(stem)
            if nutrient == .sodium, grams == nil, let salt = perServingIfListed("salt") {
                grams = salt / Self.saltPerSodium
                sodiumFromSalt = true
            }
            guard let grams else { continue }
            // Grams to the label's unit, trimmed of the float noise the multiplication
            // leaves (0.19 g is 190 mg, not 190.00000000000003).
            let value = (grams * nutrient.unit.perGram * 1_000_000).rounded() / 1_000_000
            if nutrient.accepts(value) {
                detail[nutrient] = value
            } else if nutrient == .sodium {
                // A negative or absurd figure is a bad community entry: left not known,
                // so there is no conversion to report either.
                sodiumFromSalt = false
            }
        }

        let kcal    = perServing("energy-kcal_serving", ["energy-kcal_100g", "energy-kcal"])
        let protein = perServing("proteins_serving", ["proteins_100g"])
        let carbs   = perServing("carbohydrates_serving", ["carbohydrates_100g"])
        let fat     = perServing("fat_serving", ["fat_100g"])

        // Describe the basis so she knows what "1" of this means.
        let hasServingData = num(n, "energy-kcal_serving") != nil || num(n, "proteins_serving") != nil
        let declared = (p["serving_size"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basis: String
        if let declared, !declared.isEmpty {
            basis = declared
        } else if hasServingData || servingQty != nil {
            basis = "1 serving"
        } else {
            basis = "100 g"          // only per-100 g data was available
        }

        let sanity = NutritionSanity.check(calories: kcal, protein: protein, carbs: carbs, fat: fat, grams: servingQty)

        return FoodHit(
            name: (p["product_name"] as? String) ?? "",
            brand: (p["brands"] as? String),
            servingDescription: basis,
            calories: sanity.calories,
            proteinG: sanity.protein,
            carbsG: sanity.carbs,
            fatG: sanity.fat,
            barcode: barcode,
            isSuspicious: sanity.isSuspicious,
            sanityNote: sanity.reason,
            detail: detail,
            sodiumFromSalt: sodiumFromSalt
        )
    }

    private static func fetch(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
