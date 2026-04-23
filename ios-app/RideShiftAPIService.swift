import Foundation

// ── Codable models matching the FastAPI response ─────────────────────────────

struct OriginResult: Codable {
    let address: String
    let lat: Double
    let lon: Double
    let fareCents: Int?

    enum CodingKeys: String, CodingKey {
        case address, lat, lon
        case fareCents = "fare_cents"
    }
}

struct CandidateResult: Codable, Identifiable {
    let candidateId: Int
    let lat: Double
    let lon: Double
    let fareCents: Int?
    let savingsCents: Int?
    let walkingDistM: Double
    let beamStep: Int

    var id: Int { candidateId }

    var fareFormatted: String {
        guard let cents = fareCents else { return "n/a" }
        return String(format: "$%.2f", Double(cents) / 100)
    }

    var savingsFormatted: String {
        guard let cents = savingsCents, cents > 0 else { return nil ?? "No saving" }
        return String(format: "saves $%.2f", Double(cents) / 100)
    }

    var walkingMinutes: Int {
        max(1, Int((walkingDistM / 80).rounded()))
    }

    var walkingFormatted: String {
        let mins = walkingMinutes
        if walkingDistM < 1000 {
            return String(format: "%.0f m · %d min walk", walkingDistM, mins)
        } else {
            return String(format: "%.1f km · %d min walk", walkingDistM / 1000, mins)
        }
    }

    enum CodingKeys: String, CodingKey {
        case candidateId  = "candidate_id"
        case lat, lon
        case fareCents    = "fare_cents"
        case savingsCents = "savings_cents"
        case walkingDistM = "walking_dist_m"
        case beamStep     = "beam_step"
    }
}

struct SearchResponse: Codable {
    let origin: OriginResult
    let bestCandidate: CandidateResult?
    let candidates: [CandidateResult]

    enum CodingKeys: String, CodingKey {
        case origin
        case bestCandidate = "best_candidate"
        case candidates
    }
}

// ── API Service ───────────────────────────────────────────────────────────────

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid server URL."
        case .serverError(let msg): return msg
        case .decodingError(let e): return "Couldn't read response: \(e.localizedDescription)"
        case .networkError(let e):  return "Network error: \(e.localizedDescription)"
        }
    }
}

@MainActor
final class RideShiftAPIService: ObservableObject {
    // ⚠️ Change this to your Mac's local IP when testing on a real device.
    // For the Simulator, localhost works fine.
    static var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        return "http://10.2.45.38:8000" // Your Mac IP
        #endif
    }

    func findBestPickup(pickup: String, destination: String) async throws -> SearchResponse {
        guard let url = URL(string: "\(Self.baseURL)/find-best-pickup") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The pipeline can take up to ~30 s — give it room
        request.timeoutInterval = 180

        let body = ["pickup_address": pickup, "destination_address": destination]
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Try to surface the FastAPI error detail
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw APIError.serverError(detail ?? "Server returned \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
