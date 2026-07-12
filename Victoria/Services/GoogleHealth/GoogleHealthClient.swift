import Foundation

/// REST client for the Google Health API v4 (`health.googleapis.com`) — the direct
/// line to the Fitbit Air, no bridge app in between. Verified against Google's own
/// discovery document (rev 2026-07-08):
///
///   GET /v4/users/me/dataTypes/{type}/dataPoints?filter=...&pageSize=...
///
/// Data types we read, and where each lands:
///   - `sleep`                        → `SleepEntry` (stages: DEEP/REM/LIGHT→core/AWAKE)
///   - `daily-resting-heart-rate`     → `VitalsEntry.restingHeartRate`
///   - `daily-heart-rate-variability` → `VitalsEntry.hrvMs`
///   - `exercise`                     → `DetectedWorkout`
///
/// Steps are deliberately NOT read here — the iPhone already supplies steps through
/// HealthKit, and a second source would double-count the ring.
///
/// Wire-format gotchas (all verified in the discovery doc, all covered by tests):
/// int64 fields arrive as JSON *strings* ("beatsPerMinute": "56", stage "minutes": "104");
/// durations as "3600s"; daily dates as {year, month, day}. Parsing is tolerant —
/// a malformed point is skipped and logged, never fatal.
enum GoogleHealthClient {

    private static let base = "https://health.googleapis.com/v4/users/me/dataTypes"

    // MARK: - Fetchers (network → parsed shapes the HealthKit merges already accept)

    /// Per-night sleep for the last `days` nights, keyed by START-OF-DAY OF THE WAKE
    /// MORNING — the same contract as `HealthKitService.dailySleep`. Naps are excluded;
    /// when a night has several sessions, the one with the most sleep wins.
    @MainActor
    static func fetchDailySleep(days: Int) async throws -> [Date: HealthKitService.NightSleep] {
        // Sleep filters on civil (user-local) end time — exactly our wake-morning key.
        let dicts = try await fetchAllPages(
            type: "sleep",
            filter: "sleep.interval.civil_end_time >= \"\(civilDateString(daysAgo: days))\"")
        return parseSleep(dataPoints: dicts)
    }

    /// Daily resting HR + HRV for the last `days` days — same shape as
    /// `HealthKitService.dailyVitals`. Missing halves stay 0, matching that contract.
    @MainActor
    static func fetchDailyVitals(days: Int) async throws -> [Date: (rhr: Double, hrv: Double)] {
        let since = civilDateString(daysAgo: days)
        async let rhrPoints = fetchAllPages(
            type: "daily-resting-heart-rate",
            filter: "daily_resting_heart_rate.date >= \"\(since)\"")
        async let hrvPoints = fetchAllPages(
            type: "daily-heart-rate-variability",
            filter: "daily_heart_rate_variability.date >= \"\(since)\"")
        return parseVitals(rhrPoints: try await rhrPoints, hrvPoints: try await hrvPoints)
    }

    /// Detected exercise sessions in the last `days` days, in `ImportableWorkout` form
    /// so `mergeDetectedWorkouts` treats them exactly like HealthKit workouts. The
    /// dedup key is the data point's stable resource name prefixed "ghealth:".
    @MainActor
    static func fetchWorkouts(days: Int) async throws -> [HealthKitService.ImportableWorkout] {
        let dicts = try await fetchAllPages(
            type: "exercise",
            filter: "exercise.interval.civil_start_time >= \"\(civilDateString(daysAgo: days))\"")
        return parseExercises(dataPoints: dicts)
    }

    // MARK: - HTTP

    enum APIError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Google Health API error \(code): \(body)"
            }
        }
    }

    /// GET one data type, following `nextPageToken` (bounded — a 14-day window of
    /// daily/session points is at most a few hundred rows; 10 pages is generous).
    @MainActor
    private static func fetchAllPages(type: String, filter: String) async throws -> [[String: Any]] {
        let token = try await GoogleHealthAuth.shared.validAccessToken()
        var all: [[String: Any]] = []
        var pageToken: String?
        for _ in 0..<10 {
            var comps = URLComponents(string: "\(base)/\(type)/dataPoints")!
            var items = [URLQueryItem(name: "filter", value: filter),
                         URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            comps.queryItems = items
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                Diagnostics.shared.log("google health \(type) HTTP \(status): \(body)", .error)
                throw APIError.http(status, body)
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            all.append(contentsOf: (json["dataPoints"] as? [[String: Any]]) ?? [])
            pageToken = json["nextPageToken"] as? String
            if pageToken == nil { break }
        }
        return all
    }

    /// "YYYY-MM-DD" for `days` ago in the user's calendar — the civil-time literal the
    /// filter grammar expects (no timezone math; Google resolves civil time per point).
    nonisolated static func civilDateString(daysAgo: Int, from now: Date = .now,
                                            calendar cal: Calendar = .current) -> String {
        let day = cal.date(byAdding: .day, value: -max(1, daysAgo), to: cal.startOfDay(for: now)) ?? now
        let c = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Parsing (pure, unit-tested against real wire shapes)

    /// Lenient numeric readers: the API sends int64 as String, doubles as NSNumber.
    nonisolated private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    nonisolated private static func minutes(_ any: Any?) -> Int {
        Int(number(any) ?? 0)
    }

    /// {year, month, day} → local start-of-day.
    nonisolated private static func date(fromCivil dict: [String: Any]?,
                                         calendar cal: Calendar) -> Date? {
        guard let dict,
              let y = number(dict["year"]), let m = number(dict["month"]),
              let d = number(dict["day"]), y > 0, m > 0, d > 0 else { return nil }
        return cal.date(from: DateComponents(year: Int(y), month: Int(m), day: Int(d)))
            .map(cal.startOfDay(for:))
    }

    /// RFC-3339 timestamp (with or without fractional seconds).
    nonisolated static func rfc3339(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// "3600s" / "3600.5s" (google-duration) → seconds.
    nonisolated static func durationSeconds(_ string: String?) -> Double? {
        guard var s = string else { return nil }
        if s.hasSuffix("s") { s.removeLast() }
        return Double(s)
    }

    nonisolated static func parseSleep(dataPoints: [[String: Any]],
                                       calendar cal: Calendar = .current)
        -> [Date: HealthKitService.NightSleep] {
        // One candidate per session; then the longest sleep per wake-day wins
        // (same "don't double-count a night" rule as the HealthKit path).
        var best: [Date: HealthKitService.NightSleep] = [:]
        for point in dataPoints {
            guard let sleep = point["sleep"] as? [String: Any] else { continue }
            let meta = sleep["metadata"] as? [String: Any]
            if (meta?["nap"] as? Bool) == true { continue }

            let interval = sleep["interval"] as? [String: Any]
            // Wake-day key: prefer the explicit civil end date; fall back to the
            // UTC end instant shifted by the session's own UTC offset.
            var day: Date? = date(fromCivil: (interval?["civilEndTime"] as? [String: Any])?["date"] as? [String: Any],
                                  calendar: cal)
            if day == nil, let end = rfc3339(interval?["endTime"] as? String) {
                let offset = durationSeconds(interval?["endUtcOffset"] as? String) ?? 0
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(identifier: "UTC")!
                let civil = utc.dateComponents([.year, .month, .day],
                                               from: end.addingTimeInterval(offset))
                day = cal.date(from: civil).map(cal.startOfDay(for:))
            }
            guard let day else { continue }

            var night = HealthKitService.NightSleep()
            let summary = sleep["summary"] as? [String: Any]
            night.asleep = minutes(summary?["minutesAsleep"])
            night.inBed = minutes(summary?["minutesInSleepPeriod"])
            for stage in (summary?["stagesSummary"] as? [[String: Any]]) ?? [] {
                let mins = minutes(stage["minutes"])
                switch stage["type"] as? String {
                case "DEEP":  night.deep += mins
                case "REM":   night.rem += mins
                case "LIGHT": night.core += mins   // Google LIGHT ≙ Apple core
                case "AWAKE": night.awake += mins
                default:      break                 // ASLEEP/RESTLESS: classic-mode, no stage bucket
                }
            }
            // CLASSIC sessions may lack a summary — fall back to summing the stage
            // segments so the night still counts.
            if night.asleep == 0 {
                for stage in (sleep["stages"] as? [[String: Any]]) ?? [] {
                    guard let type = stage["type"] as? String, type != "AWAKE" else { continue }
                    if let start = rfc3339(stage["startTime"] as? String),
                       let end = rfc3339(stage["endTime"] as? String) {
                        night.asleep += Int(end.timeIntervalSince(start) / 60)
                    }
                }
            }
            guard night.asleep > 0 else { continue }
            if night.inBed == 0 { night.inBed = night.asleep + night.awake }

            if let current = best[day], current.asleep >= night.asleep { continue }
            best[day] = night
        }
        return best
    }

    nonisolated static func parseVitals(rhrPoints: [[String: Any]],
                                        hrvPoints: [[String: Any]],
                                        calendar cal: Calendar = .current)
        -> [Date: (rhr: Double, hrv: Double)] {
        var out: [Date: (rhr: Double, hrv: Double)] = [:]
        for point in rhrPoints {
            guard let payload = point["dailyRestingHeartRate"] as? [String: Any],
                  let day = date(fromCivil: payload["date"] as? [String: Any], calendar: cal),
                  let bpm = number(payload["beatsPerMinute"]), bpm > 0 else { continue }
            out[day, default: (0, 0)].rhr = bpm
        }
        for point in hrvPoints {
            guard let payload = point["dailyHeartRateVariability"] as? [String: Any],
                  let day = date(fromCivil: payload["date"] as? [String: Any], calendar: cal),
                  let ms = number(payload["averageHeartRateVariabilityMilliseconds"]), ms > 0
            else { continue }
            out[day, default: (0, 0)].hrv = ms
        }
        return out
    }

    nonisolated static func parseExercises(dataPoints: [[String: Any]])
        -> [HealthKitService.ImportableWorkout] {
        dataPoints.compactMap { point in
            guard let exercise = point["exercise"] as? [String: Any],
                  let interval = exercise["interval"] as? [String: Any],
                  let start = rfc3339(interval["startTime"] as? String) else { return nil }

            // Prefer active duration (excludes pauses); fall back to the interval.
            var seconds = durationSeconds(exercise["activeDuration"] as? String) ?? 0
            if seconds <= 0, let end = rfc3339(interval["endTime"] as? String) {
                seconds = end.timeIntervalSince(start)
            }
            let mins = Int((seconds / 60).rounded())
            guard mins >= 1 else { return nil }

            // Stable identity: the data point resource name. Prefixed so it can never
            // collide with a HealthKit UUID in the same table.
            let name = (point["name"] as? String)
                ?? "\(exercise["exerciseType"] as? String ?? "workout")-\(start.timeIntervalSince1970)"

            let metrics = exercise["metricsSummary"] as? [String: Any]
            let source = (point["dataSource"] as? [String: Any])
            let device = (source?["device"] as? [String: Any])?["displayName"] as? String

            return HealthKitService.ImportableWorkout(
                healthKitUUID: "ghealth:\(name)",
                date: start,
                activity: activityLabel(type: exercise["exerciseType"] as? String,
                                        displayName: exercise["displayName"] as? String),
                durationMinutes: mins,
                caloriesBurned: number(metrics?["caloriesKcal"]) ?? 0,
                sourceName: device ?? "Fitbit")
        }
    }

    /// Human label for Google's exercise enum — mirrors `HealthKitService.activityLabel`
    /// for the common tracker-detected types, then falls back to the API's own display
    /// name, then to a prettified enum ("CIRCUIT_TRAINING" → "Circuit training").
    nonisolated static func activityLabel(type: String?, displayName: String?) -> String {
        switch type {
        case "RUNNING", "TREADMILL", "TRAIL_RUN", "INCLINE_RUN": return "Running"
        case "WALKING", "TREADMILL_WALK", "POWER_WALKING", "INCLINE_WALK",
             "STROLLER_WALK", "NORDIC_WALKING":                  return "Walking"
        case "HIKING", "BACKPACKING", "RUCKING":                 return "Hiking"
        case "BIKING", "OUTDOOR_BIKE", "MOUNTAIN_BIKE", "STATIONARY_BIKE",
             "SPINNING", "ELECTRIC_BIKE":                        return "Cycling"
        case "SWIMMING", "SWIMMING_POOL", "SWIMMING_OPEN_WATER": return "Swimming"
        case "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHTS", "WEIGHT_MACHINES",
             "FREE_WEIGHTS", "FUNCTIONAL_STRENGTH_TRAINING", "POWERLIFTING",
             "BODY_WEIGHT":                                      return "Strength training"
        case "HIIT", "INTERVAL_WORKOUT", "TABATA_WORKOUT":       return "HIIT"
        case "YOGA", "YOGA_BIKRAM", "YOGA_HATHA", "YOGA_POWER", "YOGA_VINYASA":
                                                                 return "Yoga"
        case "PILATES":                                          return "Pilates"
        case "ELLIPTICAL":                                       return "Elliptical"
        case "ROWING", "ROWING_MACHINE":                         return "Rowing"
        case "STAIRCLIMBER", "STEP_TRAINING":                    return "Stair climbing"
        case "DANCING", "ZUMBA", "HIP_HOP", "BALLROOM_DANCE", "JAZZ_DANCE",
             "MODERN_DANCE", "BREAKDANCING":                     return "Dance"
        case "SOCCER":                                           return "Soccer"
        case "BASKETBALL":                                       return "Basketball"
        case "TENNIS":                                           return "Tennis"
        case "CORE_TRAINING":                                    return "Core training"
        case "STRETCHING":                                       return "Stretching"
        case "CARDIO_WORKOUT", "CROSS_TRAINING", "AEROBIC_WORKOUT",
             "CARDIO_SCULPT":                                    return "Cardio"
        default:
            if let displayName, !displayName.isEmpty { return displayName }
            guard let type, !type.isEmpty, type != "EXERCISE_TYPE_UNSPECIFIED",
                  type != "OTHER", type != "WORKOUT", type != "SPORT" else { return "Workout" }
            let pretty = type.replacingOccurrences(of: "_", with: " ").lowercased()
            return pretty.prefix(1).uppercased() + pretty.dropFirst()
        }
    }
}
