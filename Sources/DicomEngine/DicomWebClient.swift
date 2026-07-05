import Foundation

extension URLRequest {
    /// Attach an HTTP Basic auth header if either credential is non-empty.
    mutating func setBasicAuth(_ user: String, _ password: String) {
        guard !user.isEmpty || !password.isEmpty,
              let tok = "\(user):\(password)".data(using: .utf8)?.base64EncodedString() else { return }
        setValue("Basic \(tok)", forHTTPHeaderField: "Authorization")
    }
}

/// DICOMweb (QIDO-RS / WADO-RS / STOW-RS) client — pure REST, no DCMTK.
public struct DicomWebClient: Sendable {
    public var baseURL: String       // e.g. http://host:8042/dicom-web
    public var username: String
    public var password: String

    public init(baseURL: String, username: String = "", password: String = "") {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        self.username = username
        self.password = password
    }

    public enum WebError: LocalizedError {
        case badURL, http(Int, String), noBoundary, decode(String)
        public var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid base URL."
            case .http(let c, let m): return "HTTP \(c)\(m.isEmpty ? "" : ": \(m)")"
            case .noBoundary: return "Response was not multipart/related."
            case .decode(let s): return "Could not parse response: \(s)"
            }
        }
    }

    private var trimmedBase: String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    /// Shared network timeout (same Settings knob as DIMSE). 0 → system default.
    static var timeout: TimeInterval {
        let t = UserDefaults.standard.object(forKey: "networkTimeout") as? Int ?? 15
        return t > 0 ? TimeInterval(t) : 60
    }

    private func request(_ url: URL, accept: String? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = Self.timeout
        r.setBasicAuth(username, password)
        if let accept { r.setValue(accept, forHTTPHeaderField: "Accept") }
        return r
    }

    // MARK: QIDO-RS — study-level query

    /// Returns one flat dictionary per study (friendly keys for the results table).
    public func queryStudies(filters: [String: String]) async throws -> [[String: String]] {
        guard var comps = URLComponents(string: "\(trimmedBase)/studies") else { throw WebError.badURL }
        var items = [URLQueryItem(name: "limit", value: "200")]
        for f in ["StudyDescription", "NumberOfStudyRelatedSeries", "ModalitiesInStudy", "PatientID"] {
            items.append(URLQueryItem(name: "includefield", value: f))
        }
        for (k, v) in filters where !v.isEmpty { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        guard let url = comps.url else { throw WebError.badURL }

        let (data, resp) = try await URLSession.shared.data(for: request(url, accept: "application/dicom+json"))
        try check(resp, data)
        if data.isEmpty { return [] }   // 204 No Content
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WebError.decode("expected a JSON array")
        }
        return arr.map { obj in
            [
                "PatientName": Self.value(obj, "00100010"),
                "PatientID": Self.value(obj, "00100020"),
                "StudyDate": Self.value(obj, "00080020"),
                "StudyDescription": Self.value(obj, "00081030"),
                "ModalitiesInStudy": Self.value(obj, "00080061"),
                "NumberOfStudyRelatedSeries": Self.value(obj, "00201206"),
                "StudyInstanceUID": Self.value(obj, "0020000D"),
            ]
        }
    }

    // MARK: QIDO-RS — series of a study

    /// Returns one flat dictionary per series of a study.
    public func querySeries(studyUID: String) async throws -> [[String: String]] {
        guard var comps = URLComponents(string: "\(trimmedBase)/studies/\(studyUID)/series") else {
            throw WebError.badURL
        }
        comps.queryItems = ["SeriesDescription", "NumberOfSeriesRelatedInstances"]
            .map { URLQueryItem(name: "includefield", value: $0) }
        guard let url = comps.url else { throw WebError.badURL }
        let (data, resp) = try await URLSession.shared.data(for: request(url, accept: "application/dicom+json"))
        try check(resp, data)
        if data.isEmpty { return [] }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WebError.decode("expected a JSON array")
        }
        return arr.map { obj in
            [
                "Modality": Self.value(obj, "00080060"),
                "SeriesNumber": Self.value(obj, "00200011"),
                "SeriesDescription": Self.value(obj, "0008103E"),
                "NumberOfSeriesRelatedInstances": Self.value(obj, "00201209"),
                "SeriesInstanceUID": Self.value(obj, "0020000E"),
            ]
        }
    }

    // MARK: QIDO-RS — instances of a series

    /// Returns one flat dictionary per instance of a series.
    public func queryInstances(studyUID: String, seriesUID: String) async throws -> [[String: String]] {
        guard var comps = URLComponents(string: "\(trimmedBase)/studies/\(studyUID)/series/\(seriesUID)/instances") else {
            throw WebError.badURL
        }
        comps.queryItems = [URLQueryItem(name: "includefield", value: "InstanceNumber")]
        guard let url = comps.url else { throw WebError.badURL }
        let (data, resp) = try await URLSession.shared.data(for: request(url, accept: "application/dicom+json"))
        try check(resp, data)
        if data.isEmpty { return [] }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WebError.decode("expected a JSON array")
        }
        return arr.map { obj in
            [
                "InstanceNumber": Self.value(obj, "00200013"),
                "SOPClassUID": Self.value(obj, "00080016"),
                "SOPInstanceUID": Self.value(obj, "00080018"),
                "Rows": Self.value(obj, "00280010"),
                "Columns": Self.value(obj, "00280011"),
            ]
        }
    }

    // MARK: WADO-RS — metadata + rendered

    /// Full DICOM-JSON metadata of one instance, flattened to (tag, vr, value) rows.
    public func instanceMetadata(studyUID: String, seriesUID: String, sopUID: String)
        async throws -> [(tag: String, vr: String, value: String)] {
        guard let url = URL(string: "\(trimmedBase)/studies/\(studyUID)/series/\(seriesUID)/instances/\(sopUID)/metadata")
        else { throw WebError.badURL }
        let (data, resp) = try await URLSession.shared.data(for: request(url, accept: "application/dicom+json"))
        try check(resp, data)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let obj = arr.first else { throw WebError.decode("expected a JSON array") }
        return obj.keys.sorted().map { tag in
            let e = obj[tag] as? [String: Any]
            return (tag: tag, vr: (e?["vr"] as? String) ?? "", value: Self.value(obj, tag))
        }
    }

    /// Server-rendered preview (JPEG/PNG bytes) of one instance.
    public func renderedInstance(studyUID: String, seriesUID: String, sopUID: String) async throws -> Data {
        guard let url = URL(string: "\(trimmedBase)/studies/\(studyUID)/series/\(seriesUID)/instances/\(sopUID)/rendered")
        else { throw WebError.badURL }
        // Single-value Accept — Orthanc 400s on "image/jpeg, image/png".
        let (data, resp) = try await URLSession.shared.data(for: request(url, accept: "image/jpeg"))
        try check(resp, data)
        return data
    }

    // MARK: WADO-RS — retrieve a study or series as multipart/related DICOM

    /// Downloads every instance of one series to `outDir`; returns the count.
    public func retrieveSeries(studyUID: String, seriesUID: String, outDir: String) async throws -> Int {
        try await retrieve(path: "studies/\(studyUID)/series/\(seriesUID)", outDir: outDir)
    }

    /// Downloads every instance of a study to `outDir`; returns the instance count.
    public func retrieveStudy(studyUID: String, outDir: String) async throws -> Int {
        try await retrieve(path: "studies/\(studyUID)", outDir: outDir)
    }

    private func retrieve(path: String, outDir: String) async throws -> Int {
        guard let url = URL(string: "\(trimmedBase)/\(path)") else { throw WebError.badURL }
        let (data, resp) = try await URLSession.shared.data(
            for: request(url, accept: "multipart/related; type=\"application/dicom\""))
        try check(resp, data)
        guard let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
              let boundary = Self.boundary(from: ct) else { throw WebError.noBoundary }

        let parts = Self.multipartBodies(data, boundary: boundary)
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        var n = 0
        for body in parts {
            try Task.checkCancellation()
            let path = (outDir as NSString).appendingPathComponent(String(format: "inst_%04d.dcm", n))
            if (try? body.write(to: URL(fileURLWithPath: path))) != nil { n += 1 }
        }
        return n
    }

    // MARK: STOW-RS — store instances

    /// POSTs the given DICOM files as multipart/related; returns (stored, failed).
    public func store(files: [String]) async throws -> (stored: Int, failed: Int) {
        guard let url = URL(string: "\(trimmedBase)/studies") else { throw WebError.badURL }
        let boundary = "DicomFlow-\(UUID().uuidString)"
        var body = Data()
        for f in files {
            try Task.checkCancellation()
            guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: f)) else { continue }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/dicom\r\n\r\n".data(using: .utf8)!)
            body.append(bytes)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var r = request(url, accept: "application/dicom+json")
        r.httpMethod = "POST"
        r.setValue("multipart/related; type=\"application/dicom\"; boundary=\(boundary)",
                   forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: r)
        try check(resp, data)
        // Count from the response's ReferencedSOPSequence (00081199) / FailedSOPSequence (00081198).
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let stored = ((obj?["00081199"] as? [String: Any])?["Value"] as? [Any])?.count ?? files.count
        let failed = ((obj?["00081198"] as? [String: Any])?["Value"] as? [Any])?.count ?? 0
        return (stored, failed)
    }

    // MARK: helpers

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw WebError.http(http.statusCode, msg)
        }
    }

    /// Read the first value of a DICOM-JSON element (handles PN `Alphabetic`, numbers, multi-value).
    static func value(_ obj: [String: Any], _ tag: String) -> String {
        guard let e = obj[tag] as? [String: Any], let vals = e["Value"] as? [Any] else { return "" }
        let strs: [String] = vals.compactMap { v in
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            if let pn = v as? [String: Any] { return pn["Alphabetic"] as? String }
            return nil
        }
        return strs.joined(separator: "\\")
    }

    static func boundary(from contentType: String) -> String? {
        for part in contentType.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("boundary=") {
                var b = String(p.dropFirst("boundary=".count))
                if b.hasPrefix("\"") && b.hasSuffix("\"") { b = String(b.dropFirst().dropLast()) }
                return b
            }
        }
        return nil
    }

    /// Split a multipart/related body into its part bodies (strips each part's headers).
    static func multipartBodies(_ data: Data, boundary: String) -> [Data] {
        let dashBoundary = Data("--\(boundary)".utf8)
        let crlfcrlf = Data("\r\n\r\n".utf8)
        var bodies: [Data] = []
        var idx = data.range(of: dashBoundary)?.upperBound
        while let start = idx {
            // Find the next boundary marker.
            let next = data.range(of: dashBoundary, in: start..<data.endIndex)?.lowerBound ?? data.endIndex
            let block = data.subdata(in: start..<next)
            if let hdrEnd = block.range(of: crlfcrlf)?.upperBound {
                var body = block.subdata(in: hdrEnd..<block.endIndex)
                // Trim the trailing CRLF before the boundary.
                if body.count >= 2, body.suffix(2) == Data("\r\n".utf8) { body = body.dropLast(2) }
                if !body.isEmpty { bodies.append(body) }
            }
            if next == data.endIndex { break }
            idx = data.range(of: dashBoundary, in: next..<data.endIndex)?.upperBound
        }
        return bodies
    }
}
