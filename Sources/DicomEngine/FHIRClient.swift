import Foundation

/// Minimal FHIR client — ImagingStudy search (R4). Pure URLSession/JSON.
public struct FHIRClient: Sendable {
    public var baseURL: String       // e.g. https://hapi.fhir.org/baseR4
    public var username: String
    public var password: String

    public init(baseURL: String, username: String = "", password: String = "") {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        self.username = username
        self.password = password
    }

    public enum FHIRError: LocalizedError {
        case badURL, http(Int, String), decode(String)
        public var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid base URL."
            case .http(let c, let m): return "HTTP \(c)\(m.isEmpty ? "" : ": \(m)")"
            case .decode(let s): return "Could not parse response: \(s)"
            }
        }
    }

    private var trimmedBase: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }

    /// GET {base}/ImagingStudy?… → one flat dict per study.
    public func searchImagingStudies(filters: [String: String]) async throws -> [[String: String]] {
        guard var comps = URLComponents(string: "\(trimmedBase)/ImagingStudy") else { throw FHIRError.badURL }
        var items = [URLQueryItem(name: "_count", value: "100")]
        for (k, v) in filters where !v.isEmpty { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        guard let url = comps.url else { throw FHIRError.badURL }

        var r = URLRequest(url: url)
        r.timeoutInterval = DicomWebClient.timeout
        r.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        r.setBasicAuth(username, password)
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FHIRError.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FHIRError.decode("expected a JSON object")
        }
        let entries = (obj["entry"] as? [[String: Any]]) ?? []
        return entries.compactMap { entry in
            guard let res = entry["resource"] as? [String: Any],
                  (res["resourceType"] as? String) == "ImagingStudy" else { return nil }
            return Self.flatten(res)
        }
    }

    private static func flatten(_ res: [String: Any]) -> [String: String] {
        func num(_ k: String) -> String { (res[k] as? NSNumber)?.stringValue ?? "" }
        let subject = res["subject"] as? [String: Any]
        let patient = (subject?["display"] as? String) ?? (subject?["reference"] as? String) ?? ""
        let modalities = (res["modality"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
        var studyUID = ""
        for id in (res["identifier"] as? [[String: Any]] ?? []) {
            if let v = id["value"] as? String {
                studyUID = v.hasPrefix("urn:oid:") ? String(v.dropFirst("urn:oid:".count)) : v
                if !studyUID.isEmpty { break }
            }
        }
        return [
            "Patient": patient,
            "Started": (res["started"] as? String) ?? "",
            "Modality": modalities.joined(separator: ", "),
            "Series": num("numberOfSeries"),
            "Instances": num("numberOfInstances"),
            "Description": (res["description"] as? String) ?? "",
            "Status": (res["status"] as? String) ?? "",
            "StudyUID": studyUID,
        ]
    }
}
