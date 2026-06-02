import Foundation
import CoreLocation
import MapKit

/// Finds the nearest healthy-food spot (grocery, salad/health-food, etc.) around a
/// coordinate using MapKit's `MKLocalSearch`. The result seeds at most ONE "nearby"
/// suggestion in `FoodSuggestionService`.
///
/// Why MapKit: it ships with iOS, needs no API key, and `MKLocalSearch` already does a
/// natural-language category search ("grocery store") with distances back. We don't draw
/// a map — we just want a name + how far — so this is a thin async wrapper.
///
/// EVERYTHING here is optional. If location is off, or the search finds nothing, the
/// caller gets `nil` and simply omits the nearby pick — the rest of suggestions are
/// unaffected. This service NEVER asks for permission or fetches the location itself;
/// `LocationService.currentLocation()` owns that, and the caller passes a coordinate in.
struct NearbyPlacesService {

    /// A nearby place we might mention: its name, a short category word for phrasing, and
    /// distance in meters (so we can pick the closest). Plain value type — `Sendable` so it
    /// rides safely out of the concurrent search task group.
    struct Place: Equatable, Sendable {
        var name: String
        /// A short, human category word for the prompt ("grocery", "salad", "café").
        var category: String?
        var distanceMeters: Double
    }

    /// The category queries we try, in priority order. Grocery first (most universally
    /// useful — "grab X on your way home"), then fresh/healthy prepared-food spots.
    /// Each entry pairs the `MKLocalSearch` natural-language query with the short word we
    /// hand the LLM for phrasing.
    private static let categories: [(query: String, word: String)] = [
        ("grocery store",      "grocery"),
        ("health food store",  "health food"),
        ("salad",              "salad"),
        ("juice bar",          "smoothie"),
    ]

    /// Find the single nearest relevant place to `coordinate`, or `nil` if none is found
    /// (or the search errors). Searches the configured categories within a tight radius
    /// and returns the closest hit overall.
    ///
    /// - Parameters:
    ///   - coordinate: where to search around (from `LocationService.currentLocation()`).
    ///   - radiusMeters: span of the search region; default ~3 km keeps results genuinely
    ///     "nearby" (a place you'd actually swing by), not across town.
    static func nearestHealthyPlace(near coordinate: CLLocationCoordinate2D,
                                    radiusMeters: CLLocationDistance = 3_000) async -> Place? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: radiusMeters,
                                        longitudinalMeters: radiusMeters)

        // Run the category searches CONCURRENTLY (they're independent network calls) so the
        // whole lookup takes ~one search's time instead of summing four — important because
        // the suggestions loader awaits this before calling the LLM.
        let hits: [Place] = await withTaskGroup(of: Place?.self) { group in
            for category in categories {
                group.addTask {
                    await search(query: category.query, word: category.word,
                                 region: region, origin: origin)
                }
            }
            var found: [Place] = []
            for await hit in group { if let hit { found.append(hit) } }
            return found
        }
        // Closest overall wins.
        return hits.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    // MARK: - One category search

    /// Run a single `MKLocalSearch` for `query` within `region` and return its closest
    /// result mapped to a `Place`. Returns `nil` on no results or any error (optional
    /// feature — failures are silent).
    private static func search(query: String,
                               word: String,
                               region: MKCoordinateRegion,
                               origin: CLLocation) async -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        // iOS 18: bias toward physical points of interest (an actual store), not addresses.
        request.resultTypes = [.pointOfInterest]

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return nil }

        // Pick the nearest mapItem that has a usable name + location.
        let places: [Place] = response.mapItems.compactMap { item in
            guard let loc = item.placemark.location else { return nil }
            let name = item.name ?? item.placemark.name
            guard let name, !name.isEmpty else { return nil }
            return Place(name: name,
                         category: word,
                         distanceMeters: loc.distance(from: origin))
        }
        return places.min(by: { $0.distanceMeters < $1.distanceMeters })
    }
}
