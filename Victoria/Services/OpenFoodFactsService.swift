import Foundation

/// Free, keyless nutrition lookup via Open Food Facts (barcode + text search).
/// Returns macros per serving when available, else per 100 g.
struct OpenFoodFactsService {

    struct FoodHit: Identifiable {
        let id = UUID()
        var name: String
        var brand: String?
        var servingDescription: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var barcode: String?
    }

    private static let userAgent = "Victoria/1.0 (bryanram2024@gmail.com)"

    static func product(barcode: String) async throws -> FoodHit? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,serving_size,nutriments")!
        let json = try await fetch(url)
        guard (json["status"] as? Int) == 1, let p = json["product"] as? [String: Any] else { return nil }
        return hit(from: p, barcode: barcode)
    }

    static func search(query: String) async throws -> [FoodHit] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=20&fields=product_name,brands,serving_size,nutriments,code")!
        let json = try await fetch(url)
        let products = (json["products"] as? [[String: Any]]) ?? []
        return products.compactMap { p in
            let h = hit(from: p, barcode: p["code"] as? String)
            return h.name.isEmpty ? nil : h
        }
    }

    // MARK: - Parsing
    private static func hit(from p: [String: Any], barcode: String?) -> FoodHit {
        let n = (p["nutriments"] as? [String: Any]) ?? [:]
        func num(_ keys: [String]) -> Double {
            for k in keys {
                if let d = n[k] as? Double { return d }
                if let s = n[k] as? String, let d = Double(s) { return d }
                if let i = n[k] as? Int { return Double(i) }
            }
            return 0
        }
        // Prefer per-serving; fall back to per-100g.
        let perServing = n["energy-kcal_serving"] != nil
        let serving = (p["serving_size"] as? String) ?? (perServing ? "1 serving" : "100 g")
        let kcal = perServing ? num(["energy-kcal_serving"]) : num(["energy-kcal_100g", "energy-kcal"])
        let protein = perServing ? num(["proteins_serving"]) : num(["proteins_100g"])
        let carbs = perServing ? num(["carbohydrates_serving"]) : num(["carbohydrates_100g"])
        let fat = perServing ? num(["fat_serving"]) : num(["fat_100g"])
        return FoodHit(
            name: (p["product_name"] as? String) ?? "",
            brand: (p["brands"] as? String),
            servingDescription: serving,
            calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat,
            barcode: barcode
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
