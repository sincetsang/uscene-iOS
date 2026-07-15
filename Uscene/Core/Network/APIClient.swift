import Foundation
import UIKit

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// Must outlive the session; URLSession retains its delegate strongly until invalidated.
    private let trustDelegate = DevServerTrustDelegate()

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // NOTE: do NOT disable proxies here — a real device may need its Wi-Fi HTTP proxy
        // (e.g. pointing at the Mac's VPN) to reach the test API.
        self.session = URLSession(
            configuration: config,
            delegate: trustDelegate,
            delegateQueue: nil
        )
    }

    func request<T: Decodable>(
        host: URL = AppConfig.v1Host,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        query: [String: String] = [:],
        multipart: MultipartFormData? = nil,
        allowRetry: Bool = true
    ) async throws -> T {
        guard var components = URLComponents(url: host.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        // Prefer persisted override; else follow system — avoid hopping to MainActor here.
        let language = UserDefaults.standard.string(forKey: "app_language")
            ?? LanguageManager.resolveSystemLanguage().apiCode
        request.setValue(language, forHTTPHeaderField: "Language")
        request.setValue(AppConfig.platform, forHTTPHeaderField: "Platform")
        request.setValue(AppConfig.appVersion, forHTTPHeaderField: "App-Version")

        if let token = KeychainStore.string(forKey: "access_token"), !token.isEmpty {
            let cleaned = token.replacingOccurrences(of: "\"", with: "")
            request.setValue("\(AppConfig.authorizationPrefix) \(cleaned)", forHTTPHeaderField: "Authorization")
        }

        if let multipart {
            request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart.body
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let startedAt = Date()
        #if DEBUG
        print("[API…] \(method) \(url.absoluteString)")
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await perform(request)
        } catch {
            // Task / URLSession cancellation is expected when map pans fast — don't treat as failure noise.
            if Self.isCancellation(error) {
                throw APIError.cancelled
            }
            APILogger.log(
                method: method,
                url: url,
                requestHeaders: Self.requestHeaderMap(from: request),
                requestBody: request.httpBody,
                response: nil,
                responseData: nil,
                error: error,
                startedAt: startedAt
            )
            throw APIError.network(error)
        }

        let httpResponse = response as? HTTPURLResponse
        APILogger.log(
            method: method,
            url: url,
            requestHeaders: Self.requestHeaderMap(from: request),
            requestBody: request.httpBody,
            response: httpResponse,
            responseData: data,
            error: nil,
            startedAt: startedAt
        )

        guard let http = httpResponse else {
            throw APIError.http(502)
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }

        let envelope: FlexibleEnvelope
        do {
            envelope = try JSONDecoder().decode(FlexibleEnvelope.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }

        if envelope.code == 200 {
            if T.self == EmptyData.self {
                return EmptyData() as! T
            }
            guard let raw = envelope.data else {
                if let empty = EmptyData() as? T { return empty }
                throw APIError.emptyData
            }
            do {
                return try JSONDecoder().decode(T.self, from: raw)
            } catch {
                // list endpoints sometimes wrap in { list: [...] }
                if let wrapped = try? JSONDecoder().decode(ListWrapper<T>.self, from: raw) {
                    return wrapped.list
                }
                throw APIError.decoding(error)
            }
        }

        if envelope.code == 401 {
            if allowRetry, await refreshTokenIfNeeded() {
                return try await self.request(
                    host: host,
                    path: path,
                    method: method,
                    body: body,
                    query: query,
                    multipart: multipart,
                    allowRetry: false
                )
            }
            throw APIError.unauthorized
        }

        throw APIError.business(code: envelope.code, message: envelope.errMsg ?? "Request failed")
    }

    private func refreshTokenIfNeeded() async -> Bool {
        guard let refresh = KeychainStore.string(forKey: "refresh_token"), !refresh.isEmpty else {
            return false
        }
        do {
            let body = try JSONEncoder().encode(["refresh_token": refresh])
            let token: TokenResponse = try await request(
                host: AppConfig.v1Host,
                path: "token/refresh",
                method: "POST",
                body: body,
                allowRetry: false
            )
            if let access = token.access_token {
                KeychainStore.set(access, forKey: "access_token")
            }
            if let refreshToken = token.refresh_token {
                KeychainStore.set(refreshToken, forKey: "refresh_token")
            }
            await MainActor.run {
                AuthStore.shared.syncFromKeychain()
            }
            return token.access_token != nil
        } catch {
            await MainActor.run {
                AuthStore.shared.logout()
            }
            return false
        }
    }

    private static func requestHeaderMap(from request: URLRequest) -> [String: String] {
        var headers: [String: String] = [:]
        request.allHTTPHeaderFields?.forEach { headers[$0.key] = $0.value }
        return headers
    }

    private static func isCancellation(_ error: Error) -> Bool {
        APIError.isCancellation(error)
    }

    /// Classic dataTask + continuation so ServerTrust challenges always resume (original working path).
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

/// Decodes `{ code, data, err_msg }` while keeping `data` as raw JSON for flexible typing.
private struct FlexibleEnvelope: Decodable {
    let code: Int
    let data: Data?
    let errMsg: String?

    enum CodingKeys: String, CodingKey {
        case code, data
        case errMsg = "err_msg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        errMsg = try container.decodeIfPresent(String.self, forKey: .errMsg)
        if container.contains(.data), try !container.decodeNil(forKey: .data) {
            let value = try container.decode(AnyCodable.self, forKey: .data)
            data = try JSONEncoder().encode(value)
        } else {
            data = nil
        }
    }
}

private struct ListWrapper<T: Decodable>: Decodable {
    let list: T
}

private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableBox($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableBox($0) })
        default:
            try container.encodeNil()
        }
    }
}

private struct AnyCodableBox: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableBox($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableBox($0) })
        default:
            try container.encodeNil()
        }
    }
}

struct MultipartFormData {
    let boundary = "Boundary-\(UUID().uuidString)"
    private(set) var body = Data()

    mutating func append(fileData: Data, name: String, fileName: String, mimeType: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    mutating func finish() {
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    }
}

enum SpotAPI {
    static func listGrid(
        swLat: Double, swLng: Double, neLat: Double, neLng: Double, category: String = ""
    ) async throws -> [SpotGrid] {
        var query: [String: String] = [
            "sw_lat": "\(swLat)",
            "sw_lng": "\(swLng)",
            "ne_lat": "\(neLat)",
            "ne_lng": "\(neLng)"
        ]
        if !category.isEmpty { query["category"] = category }
        let response: SpotGridResponse = try await APIClient.shared.request(path: "spot/list_grid", query: query)
        return response.grids ?? []
    }

    static func listPithy(
        swLat: Double, swLng: Double, neLat: Double, neLng: Double, page: Int = 1, category: String = ""
    ) async throws -> [MapSpot] {
        var query: [String: String] = [
            "sw_lat": "\(swLat)",
            "sw_lng": "\(swLng)",
            "ne_lat": "\(neLat)",
            "ne_lng": "\(neLng)",
            "page": "\(page)",
            "page_size": "20"
        ]
        if !category.isEmpty { query["category"] = category }
        let response: SpotPithyResponse = try await APIClient.shared.request(path: "spot/list_pithy", query: query)
        return response.points ?? []
    }

    static func nearby(
        latitude: Double, longitude: Double, category: String = "", page: Int = 1
    ) async throws -> [NearbySpotItem] {
        try await nearbyPage(latitude: latitude, longitude: longitude, category: category, page: page).items
    }

    static func nearbyPage(
        latitude: Double, longitude: Double, category: String = "", page: Int = 1
    ) async throws -> (items: [NearbySpotItem], total: Int) {
        var query: [String: String] = [
            "latitude": "\(latitude)",
            "longitude": "\(longitude)",
            "page": "\(page)",
            "page_size": "20"
        ]
        if !category.isEmpty { query["category"] = category }
        let response: SpotListResponse = try await APIClient.shared.request(
            path: "spot/list_by_distance_v2",
            query: query
        )
        let items = (response.points ?? []).map { NearbySpotItem(point: $0) }
        return (items, response.total_count ?? items.count)
    }

    static func search(
        latitude: Double, longitude: Double, keyword: String, radius: Int = 5000
    ) async throws -> [NearbySpotItem] {
        let query: [String: String] = [
            "latitude": "\(latitude)",
            "longitude": "\(longitude)",
            "radius": "\(radius)",
            "sort_by": "distance",
            "keyword": keyword
        ]
        let response: SpotListResponse = try await APIClient.shared.request(path: "spot/list_v2", query: query)
        return (response.points ?? []).map { NearbySpotItem(point: $0) }
    }

    static func detail(spotId: Int) async throws -> SpotDetailPayload {
        try await APIClient.shared.request(
            path: "spot/detail",
            query: ["spot_id": "\(spotId)"]
        )
    }

    static func categories() async throws -> [CategoryItem] {
        try await APIClient.shared.request(path: "spot/category")
    }

    static func create(_ body: CreateSpotBody) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "spot/create",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func update(_ body: UpdateSpotBody) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "spot/update",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func like(spotId: Int) async throws {
        let body = try JSONEncoder().encode(["spot_id": spotId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "spot/like",
            method: "POST",
            body: body
        )
    }

    static func likedList() async throws -> [OwnedSpotRow] {
        let response: LikedSpotsResponse = try await APIClient.shared.request(path: "spot/like/list")
        return response.all
    }

    static func mySpots(status: Int, page: Int = 1, keyword: String = "") async throws -> OwnedSpotListResponse {
        try await APIClient.shared.request(
            path: "user/spot",
            query: [
                "status": "\(status)",
                "page": "\(page)",
                "page_size": "20",
                "keyword": keyword
            ]
        )
    }

    static func reverseGeocode(latitude: Double, longitude: Double) async throws -> String? {
        let payload = try await reverseAddress(latitude: latitude, longitude: longitude)
        return payload.displayAddress
    }

    static func reverseAddress(latitude: Double, longitude: Double) async throws -> SpotAddressPayload {
        try await APIClient.shared.request(
            path: "spot/address",
            query: [
                "latitude": "\(latitude)",
                "longitude": "\(longitude)"
            ]
        )
    }

    static func comments(spotId: Int, page: Int = 1) async throws -> [ProductComment] {
        do {
            let response: ProductCommentList = try await APIClient.shared.request(
                path: "spot/comment/list",
                query: [
                    "spot_id": "\(spotId)",
                    "page": "\(page)",
                    "page_size": "20"
                ]
            )
            if let list = response.list, !list.isEmpty { return list }
        } catch {
            // Some envs return a bare array
        }
        return try await APIClient.shared.request(
            path: "spot/comment/list",
            query: [
                "spot_id": "\(spotId)",
                "page": "\(page)",
                "page_size": "20"
            ]
        )
    }
}

enum MediaAPI {
    static func presign(fileName: String) async throws -> PresignedUpload {
        let body = try JSONEncoder().encode([fileName])
        let items: [PresignedUpload] = try await APIClient.shared.request(
            path: "image/get_presigned_url",
            method: "POST",
            body: body
        )
        guard let first = items.first else { throw APIError.emptyData }
        return first
    }

    /// Returns file_key for spot create/update.
    static func uploadForSpot(_ image: UIImage) async throws -> String {
        let fileName = "ios_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).jpg"
        let signed = try await presign(fileName: fileName)
        guard let uploadURLString = signed.upload_url,
              let uploadURL = URL(string: uploadURLString),
              let fileKey = signed.file_key,
              let data = image.jpegData(compressionQuality: 0.85) else {
            throw APIError.emptyData
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 502)
        }
        return fileKey
    }
}

enum UserAPI {
    static func verificationCodes(status: String = "unused") async throws -> [VerificationCode] {
        // RN uses all / used / unused
        do {
            let response: VerificationCodeListResponse = try await APIClient.shared.request(
                path: "user/verification_code/list",
                query: ["status": status]
            )
            if !response.all.isEmpty { return response.all }
        } catch {
            // Some envs return a bare array
        }
        return try await APIClient.shared.request(
            path: "user/verification_code/list",
            query: ["status": status]
        )
    }

    static func updateProfile(nickname: String, avatarURL: String) async throws {
        let body = try JSONEncoder().encode([
            "nickname": nickname,
            "avatar_url": avatarURL
        ])
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/profile",
            method: "POST",
            body: body
        )
    }

    static func updateDescription(_ description: String) async throws {
        let body = try JSONEncoder().encode(["description": description])
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/description",
            method: "POST",
            body: body
        )
    }

    static func statistics() async throws -> UserStatistics {
        try await APIClient.shared.request(path: "user/statistics/data")
    }

    static func updateLatLng(latitude: Double, longitude: Double) async throws {
        let body = try JSONEncoder().encode([
            "lat": latitude,
            "lng": longitude
        ])
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/latlng",
            method: "POST",
            body: body
        )
    }

    static func inviteInfo() async throws -> InviteInfo {
        try await APIClient.shared.request(path: "user/invite")
    }

    static func premiumInfo() async throws -> PremiumInfo {
        try await APIClient.shared.request(path: "premium/info")
    }

    static func otherInfo(userId: Int) async throws -> OtherUserPayload {
        try await APIClient.shared.request(
            path: "user/info/other",
            query: ["user_id": "\(userId)"]
        )
    }

    static func follow(userId: Int) async throws -> FollowResult {
        let body = try JSONEncoder().encode(["user_id": userId])
        return try await APIClient.shared.request(
            path: "user/follow",
            method: "POST",
            body: body
        )
    }

    static func checkins(userId: Int, page: Int = 1) async throws -> [CheckinFeedItem] {
        let response: UserCheckinListResponse = try await APIClient.shared.request(
            path: "user/checkin/list",
            query: [
                "page": "\(page)",
                "page_size": "20",
                "user_id": "\(userId)"
            ]
        )
        return response.all
    }
}

enum ProductAPI {
    static func list() async throws -> [ShopProduct] {
        let response: ProductListResponse = try await APIClient.shared.request(path: "product/list")
        return response.products ?? []
    }

    static func search(keyword: String, sortBy: String = "created_at") async throws -> [ShopProduct] {
        let response: ProductListResponse = try await APIClient.shared.request(
            path: "product/search",
            query: [
                "keyword": keyword,
                "sort_by": sortBy
            ]
        )
        return response.products ?? []
    }
}

enum ChatAPI {
    static func recommended() async throws -> [ChatRecommended] {
        try await APIClient.shared.request(path: "chat/recommended")
    }

    static func conversations() async throws -> [ChatConversation] {
        try await APIClient.shared.request(path: "chat/conversations")
    }

    static func thread(id: String) async throws -> [ChatThreadMessage] {
        try await APIClient.shared.request(path: "chat/conversation/\(id)")
    }

    static func send(content: String, conversationId: String?, isNew: Bool, city: String) async throws -> ChatMessagePayload {
        struct Body: Encodable {
            let conversation_id: String
            let content: String
            let is_new_chat: Bool
            let city: String
        }
        let body = try JSONEncoder().encode(
            Body(
                conversation_id: conversationId ?? "",
                content: content,
                is_new_chat: isNew,
                city: city
            )
        )
        return try await APIClient.shared.request(
            path: "chat/message",
            method: "POST",
            body: body
        )
    }

    static func deleteConversation(id: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "chat/conversation/\(id)",
            method: "DELETE"
        )
    }
}

enum MessageAPI {
    static func list(page: Int = 1) async throws -> MessageListResponse {
        try await APIClient.shared.request(
            path: "checkin/message/list",
            query: ["page": "\(page)", "page_size": "20"]
        )
    }

    static func unreadCount() async throws -> Int {
        let response: UnreadCountResponse = try await APIClient.shared.request(
            path: "checkin/message/unread_count"
        )
        return response.unread_count ?? 0
    }
}

enum AuthAPI {
    static func sendEmailCaptcha(email: String) async throws {
        let body = try JSONEncoder().encode(["email": email])
        let _: EmptyData = try await APIClient.shared.request(
            path: "email/captcha",
            method: "POST",
            body: body
        )
    }

    static func emailLogin(email: String, captcha: String, inviteCode: String = "") async throws -> TokenResponse {
        let body = try JSONEncoder().encode([
            "email": email,
            "captcha": captcha,
            "invite_code": inviteCode
        ])
        return try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "email/login",
            method: "POST",
            body: body
        )
    }

    static func appleLogin(idToken: String, inviteCode: String = "") async throws -> TokenResponse {
        let body = try JSONEncoder().encode([
            "id_token": idToken,
            "invite_code": inviteCode
        ])
        return try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "auth/apple/login",
            method: "POST",
            body: body
        )
    }

    static func googleLogin(idToken: String, inviteCode: String = "") async throws -> TokenResponse {
        let body = try JSONEncoder().encode([
            "login_type": "ios",
            "invite_code": inviteCode,
            "id_token": idToken
        ])
        return try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "auth/google/login",
            method: "POST",
            body: body
        )
    }

    static func userInfo() async throws -> UserProfile {
        try await APIClient.shared.request(path: "user/info")
    }
}

enum CheckinAPI {
    static func create(
        spotId: Int,
        content: String,
        imageURLs: [String],
        tags: [String] = [],
        isPrivate: Bool = false
    ) async throws -> Checkin {
        struct Body: Encodable {
            let check_in_point_id: Int
            let content: String
            let image_urls: [String]
            let tags: [String]
            let `private`: Bool
        }
        let body = try JSONEncoder().encode(
            Body(
                check_in_point_id: spotId,
                content: content,
                image_urls: imageURLs,
                tags: tags,
                private: isPrivate
            )
        )
        return try await APIClient.shared.request(
            path: "checkin/create",
            method: "POST",
            body: body
        )
    }

    static func detail(checkinId: Int) async throws -> CheckinDetailPayload {
        try await APIClient.shared.request(
            path: "checkin/detail",
            query: ["checkin_id": "\(checkinId)"]
        )
    }

    static func like(checkinId: Int) async throws {
        let body = try JSONEncoder().encode(["checkin_id": checkinId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/like",
            method: "POST",
            body: body
        )
    }

    static func addComment(checkinId: Int, content: String, city: String = "") async throws {
        struct Body: Encodable {
            let checkin_id: Int
            let content: String
            let city: String
        }
        let body = try JSONEncoder().encode(Body(checkin_id: checkinId, content: content, city: city))
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/comment/add",
            method: "POST",
            body: body
        )
    }

    static func commentList(checkinId: Int) async throws -> [CheckinCommentThread] {
        do {
            let response: CheckinCommentListResponse = try await APIClient.shared.request(
                path: "checkin/comment/list",
                query: ["checkin_id": "\(checkinId)"]
            )
            if !response.all.isEmpty { return response.all }
        } catch {
            // fall through to bare array
        }
        return try await APIClient.shared.request(
            path: "checkin/comment/list",
            query: ["checkin_id": "\(checkinId)"]
        )
    }

    static func replyComment(checkinId: Int, commentId: Int, content: String, city: String = "") async throws {
        struct Body: Encodable {
            let checkin_id: Int
            let comment_id: Int
            let content: String
            let city: String
        }
        let body = try JSONEncoder().encode(
            Body(checkin_id: checkinId, comment_id: commentId, content: content, city: city)
        )
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/comment/reply",
            method: "POST",
            body: body
        )
    }

    static func likeComment(checkinId: Int, commentId: Int) async throws {
        struct Body: Encodable {
            let checkin_id: Int
            let comment_id: Int
        }
        let body = try JSONEncoder().encode(Body(checkin_id: checkinId, comment_id: commentId))
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/comment/like",
            method: "POST",
            body: body
        )
    }

    static func deleteComment(checkinId: Int, commentId: Int) async throws {
        struct Body: Encodable {
            let checkin_id: Int
            let comment_id: Int
        }
        let body = try JSONEncoder().encode(Body(checkin_id: checkinId, comment_id: commentId))
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/comment/delete",
            method: "POST",
            body: body
        )
    }

    static func tags() async throws -> [CheckinTag] {
        do {
            let tags: [CheckinTag] = try await APIClient.shared.request(path: "checkin/tags")
            return tags
        } catch {
            struct Wrap: Decodable { let tags: [CheckinTag]?; let list: [CheckinTag]? }
            let wrap: Wrap = try await APIClient.shared.request(path: "checkin/tags")
            return wrap.tags ?? wrap.list ?? []
        }
    }

    static func feed(latitude: Double, longitude: Double, page: Int = 1, topicId: Int = 0) async throws -> [CheckinFeedItem] {
        let response: CheckinFeedResponse = try await APIClient.shared.request(
            path: "checkin/list",
            query: [
                "page": "\(page)",
                "page_size": "20",
                "latitude": "\(latitude)",
                "longitude": "\(longitude)",
                "topic_id": "\(topicId)"
            ]
        )
        return response.all
    }

    static func spotLatest(spotId: Int, page: Int = 1) async throws -> [CheckinFeedItem] {
        let response: CheckinFeedResponse = try await APIClient.shared.request(
            path: "spot/checkin/latest",
            query: [
                "page": "\(page)",
                "page_size": "20",
                "spot_id": "\(spotId)"
            ]
        )
        return response.all
    }

    static func spotRecommended(spotId: Int, page: Int = 1) async throws -> [CheckinFeedItem] {
        let response: CheckinFeedResponse = try await APIClient.shared.request(
            path: "spot/checkin/recommended",
            query: [
                "page": "\(page)",
                "page_size": "20",
                "spot_id": "\(spotId)"
            ]
        )
        return response.all
    }

    static func publishRestrict() async throws -> CheckinPublishRestrict {
        try await APIClient.shared.request(path: "checkin/publish/restrict")
    }

    static func uploadImage(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.emptyData
        }
        var form = MultipartFormData()
        form.append(fileData: data, name: "file", fileName: "upload.jpg", mimeType: "image/jpeg")
        form.finish()
        let response: UploadImageResponse = try await APIClient.shared.request(
            path: "user/upload_image",
            method: "POST",
            multipart: form
        )
        guard let url = response.resolvedURL else { throw APIError.emptyData }
        return url
    }

    static func delete(checkinId: Int) async throws {
        let body = try JSONEncoder().encode(["checkin_id": checkinId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/delete",
            method: "POST",
            body: body
        )
    }

    static func updatePrivate(checkinId: Int, isPrivate: Bool) async throws {
        struct Body: Encodable {
            let checkin_id: Int
            let `private`: Bool
        }
        let body = try JSONEncoder().encode(Body(checkin_id: checkinId, private: isPrivate))
        let _: EmptyData = try await APIClient.shared.request(
            path: "checkin/private/update",
            method: "POST",
            body: body
        )
    }
}

enum CommerceAPI {
    static func productDetail(productId: Int, isOwner: Int = 0) async throws -> ProductDetail {
        try await APIClient.shared.request(
            path: "product/detail",
            query: ["product_id": "\(productId)", "is_owner": "\(isOwner)"]
        )
    }

    static func productComments(productId: Int, page: Int = 1) async throws -> [ProductComment] {
        let response: ProductCommentList = try await APIClient.shared.request(
            path: "product/comment/list",
            query: [
                "product_id": "\(productId)",
                "page": "\(page)",
                "page_size": "20"
            ]
        )
        return response.list ?? []
    }

    static func addOrderComment(orderId: Int, star: Int, comment: String) async throws {
        struct Body: Encodable {
            let order_id: Int
            let star: Int
            let comment: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, star: star, comment: comment))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/comment/add",
            method: "POST",
            body: body
        )
    }

    static func updateOrderComment(orderId: Int, star: Int, comment: String) async throws {
        struct Body: Encodable {
            let order_id: Int
            let star: Int
            let comment: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, star: star, comment: comment))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/comment/update",
            method: "POST",
            body: body
        )
    }

    static func deleteOrderComment(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/comment/delete",
            method: "POST",
            body: body
        )
    }

    static func favoriteAdd(productId: Int) async throws {
        let body = try JSONEncoder().encode(["product_id": productId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/favorite/add",
            method: "POST",
            body: body
        )
    }

    static func favoriteDelete(productId: Int) async throws {
        let body = try JSONEncoder().encode(["product_id": productId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/favorite/delete",
            method: "POST",
            body: body
        )
    }

    static func myProducts(unpublished: String = "", page: Int = 1) async throws -> UserProductListResponse {
        try await APIClient.shared.request(
            path: "user/product",
            query: [
                "unpublished": unpublished,
                "page": "\(page)",
                "page_size": "20"
            ]
        )
    }

    static func productFavorites(page: Int = 1) async throws -> UserProductListResponse {
        try await APIClient.shared.request(
            path: "user/product/favorites",
            query: ["page": "\(page)", "page_size": "20"]
        )
    }

    static func productVisitHistory(page: Int = 1) async throws -> UserProductListResponse {
        try await APIClient.shared.request(
            path: "user/product/visit_history",
            query: ["page": "\(page)", "page_size": "20"]
        )
    }

    static func tags() async throws -> [ProductTag] {
        do {
            let tags: [ProductTag] = try await APIClient.shared.request(path: "product/tag/list")
            return tags
        } catch {
            struct Wrap: Decodable { let tags: [ProductTag]?; let list: [ProductTag]? }
            let wrap: Wrap = try await APIClient.shared.request(path: "product/tag/list")
            return wrap.tags ?? wrap.list ?? []
        }
    }

    static func createProduct(_ body: CreateSellerProductBody) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/create",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func updateProduct(_ body: UpdateSellerProductBody) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/update",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func publishProduct(productId: Int) async throws {
        let body = try JSONEncoder().encode(["product_id": productId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/publish",
            method: "POST",
            body: body
        )
    }

    static func unpublishProduct(productId: Int) async throws {
        let body = try JSONEncoder().encode(["product_id": productId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/unpublish",
            method: "POST",
            body: body
        )
    }

    static func addressList() async throws -> [UserAddress] {
        do {
            let list: [UserAddress] = try await APIClient.shared.request(path: "user/address/list")
            return list
        } catch {
            let wrapped: AddressListResponse = try await APIClient.shared.request(path: "user/address/list")
            return wrapped.all
        }
    }

    static func addAddress(_ body: UpsertAddressBody) async throws {
        var payload = body
        payload.address_id = nil
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/address/add",
            method: "POST",
            body: JSONEncoder().encode(payload)
        )
    }

    static func updateAddress(_ body: UpsertAddressBody) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/address/update",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func deleteAddress(addressId: Int) async throws {
        let body = try JSONEncoder().encode(["address_id": addressId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/address/delete",
            method: "POST",
            body: body
        )
    }

    static func createProductOrder(_ body: CreateProductOrderBody) async throws -> CommerceOrder {
        try await APIClient.shared.request(
            path: "product/order/create",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func productOrderDetail(orderId: Int, isSeller: Int = 0) async throws -> CommerceOrder {
        try await APIClient.shared.request(
            path: "product/order/detail",
            query: ["order_id": "\(orderId)", "is_seller": "\(isSeller)"]
        )
    }

    static func productPayInfo(orderId: Int) async throws -> PayInfo {
        try await APIClient.shared.request(
            path: "product/order/pay_info",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func productPayStatus(orderId: Int) async throws -> PayStatus {
        try await APIClient.shared.request(
            path: "product/order/pay_status",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func productPayReport(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/pay_report",
            method: "POST",
            body: body
        )
    }

    static func cancelProductOrder(orderId: Int, reason: String = "") async throws {
        struct Body: Encodable {
            let order_id: Int
            let reason: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, reason: reason))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/cancel",
            method: "POST",
            body: body
        )
    }

    static func confirmReceipt(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/confirm_receipt",
            method: "POST",
            body: body
        )
    }

    static func confirmShipment(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/confirm_shipment",
            method: "POST",
            body: body
        )
    }

    static func applyRefund(orderId: Int, reason: String) async throws {
        struct Body: Encodable {
            let order_id: Int
            let reason: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, reason: reason))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/apply_refund",
            method: "POST",
            body: body
        )
    }

    static func handleRefund(refundId: Int, approve: Bool, rejectReason: String = "") async throws {
        struct Body: Encodable {
            let refund_id: Int
            let approve: Bool
            let reject_reason: String
        }
        let body = try JSONEncoder().encode(Body(refund_id: refundId, approve: approve, reject_reason: rejectReason))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/handle_refund",
            method: "POST",
            body: body
        )
    }

    static func cancelByMerchant(orderId: Int, reason: String = "") async throws {
        struct Body: Encodable {
            let order_id: Int
            let reason: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, reason: reason))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/cancel_by_merchant",
            method: "POST",
            body: body
        )
    }

    static func updateOrderPrice(orderId: Int, price: Double) async throws {
        struct Body: Encodable {
            let order_id: Int
            let price: Double
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, price: price))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/update_price",
            method: "POST",
            body: body
        )
    }

    static func updateOrderAddress(orderId: Int, name: String, phone: String, address: String) async throws {
        struct Body: Encodable {
            let order_id: Int
            let name: String
            let phone: String
            let address: String
        }
        let body = try JSONEncoder().encode(Body(order_id: orderId, name: name, phone: phone, address: address))
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/update_address",
            method: "POST",
            body: body
        )
    }

    static func deleteOrder(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "product/order/delete",
            method: "POST",
            body: body
        )
    }

    static func bought(
        page: Int = 1,
        status: String = "",
        pendingRefund: Int = 0,
        pendingComment: Int = 0
    ) async throws -> MarketplaceOrderListResponse {
        var query = [
            "page": "\(page)",
            "page_size": "20",
            "pending_comment": "\(pendingComment)",
            "pending_refund": "\(pendingRefund)"
        ]
        if !status.isEmpty { query["status"] = status }
        return try await APIClient.shared.request(path: "user/product/bought", query: query)
    }

    static func sold(page: Int = 1, status: String = "", pendingRefund: Int = 0) async throws -> MarketplaceOrderListResponse {
        var query = [
            "page": "\(page)",
            "page_size": "20",
            "pending_comment": "0",
            "pending_refund": "\(pendingRefund)"
        ]
        if !status.isEmpty { query["status"] = status }
        return try await APIClient.shared.request(path: "user/product/sold", query: query)
    }

    static func createCodeOrder(_ body: CreateCodeOrderBody) async throws -> CommerceOrder {
        try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "order/create",
            method: "POST",
            body: JSONEncoder().encode(body)
        )
    }

    static func payMethods() async throws -> [PayMethod] {
        do {
            let response: PayMethodListResponse = try await APIClient.shared.request(path: "pay/method/list")
            if !response.all.isEmpty { return response.all }
        } catch {
            // Some envs return a bare array
        }
        return try await APIClient.shared.request(path: "pay/method/list")
    }

    static func codeOrders(status: String = "") async throws -> [CommerceOrder] {
        let response: OrderListResponse = try await APIClient.shared.request(
            path: "order/list",
            query: ["status": status]
        )
        return response.items ?? []
    }

    static func codeOrderDetail(orderId: Int) async throws -> CommerceOrder {
        try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "order/detail",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func codePayInfo(orderId: Int) async throws -> PayInfo {
        try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "order/pay_info",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func codePayStatus(orderId: Int) async throws -> PayStatus {
        try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "order/pay_status",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func cancelCodeOrder(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "order/cancel",
            method: "POST",
            body: body
        )
    }

    static func memberConfig() async throws -> [MemberPlan] {
        try await APIClient.shared.request(path: "member/config")
    }

    static func memberInfo() async throws -> MemberInfo {
        try await APIClient.shared.request(path: "user/member/info")
    }

    static func createMemberOrder(memberId: Int, payType: String = "ETH") async throws -> CommerceOrder {
        try await APIClient.shared.request(
            path: "member/order/create",
            method: "POST",
            body: JSONEncoder().encode(CreateMemberOrderBody(member_id: memberId, pay_type: payType))
        )
    }

    static func memberOrders() async throws -> [CommerceOrder] {
        let response: OrderListResponse = try await APIClient.shared.request(path: "user/member/order/list")
        return response.records ?? response.items ?? []
    }

    static func memberOrderDetail(orderId: Int) async throws -> CommerceOrder {
        try await APIClient.shared.request(
            path: "member/order/detail",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func memberPayInfo(orderId: Int) async throws -> PayInfo {
        try await APIClient.shared.request(
            path: "member/order/pay_info",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func memberPayStatus(orderId: Int) async throws -> PayStatus {
        try await APIClient.shared.request(
            path: "member/order/pay_status",
            query: ["order_id": "\(orderId)"]
        )
    }

    static func cancelMemberOrder(orderId: Int) async throws {
        let body = try JSONEncoder().encode(["order_id": orderId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "member/order/cancel",
            method: "POST",
            body: body
        )
    }

    static func bills(currency: String, page: Int = 1) async throws -> [WalletBill] {
        let response: BillListResponse = try await APIClient.shared.request(
            host: AppConfig.v2Host,
            path: "user/bill",
            query: [
                "page": "\(page)",
                "page_size": "20",
                "currency": currency
            ]
        )
        return response.bills ?? []
    }

    static func withdraw(amount: Double, address: String, currency: String) async throws {
        struct Body: Encodable {
            let currency: String
            let amount: Double
            let address: String
        }
        let body = try JSONEncoder().encode(Body(currency: currency, amount: amount, address: address))
        let _: EmptyData = try await APIClient.shared.request(
            path: "user/withdraw",
            method: "POST",
            body: body
        )
    }

    static func withdrawLatest() async throws -> WithdrawLatest {
        try await APIClient.shared.request(path: "user/withdraw/latest")
    }
}

enum SystemAPI {
    static func otaLatest() async throws -> OTAInfo {
        try await APIClient.shared.request(path: "ota/latest")
    }

    static func levelConfig() async throws -> [LevelConfig] {
        do {
            let list: [LevelConfig] = try await APIClient.shared.request(path: "level/config")
            if !list.isEmpty { return list }
        } catch {
            // wrapped payload
        }
        let wrap: LevelConfigList = try await APIClient.shared.request(path: "level/config")
        return wrap.all
    }

    static func advertisements(latitude: Double, longitude: Double, radius: Int = 5000) async throws -> [AdvertisementItem] {
        let response: AdvertisementListResponse = try await APIClient.shared.request(
            path: "advertisement/list",
            query: [
                "page": "1",
                "page_size": "20",
                "sort_by": "distance",
                "latitude": "\(latitude)",
                "longitude": "\(longitude)",
                "radius": "\(radius)"
            ]
        )
        return response.all
    }

    static func claimAd(advertisementId: Int) async throws {
        let body = try JSONEncoder().encode(["advertisement_id": advertisementId])
        let _: EmptyData = try await APIClient.shared.request(
            path: "advertisement/claim",
            method: "POST",
            body: body
        )
    }

    static func complaintTypes() async throws -> [ComplaintType] {
        do {
            let types: [ComplaintType] = try await APIClient.shared.request(path: "complaint/type/list")
            return types
        } catch {
            struct Wrap: Decodable { let list: [ComplaintType]?; let types: [ComplaintType]? }
            let wrap: Wrap = try await APIClient.shared.request(path: "complaint/type/list")
            return wrap.list ?? wrap.types ?? []
        }
    }

    static func reportSpot(spotId: Int, type: String, content: String) async throws {
        struct Body: Encodable {
            let spot_id: Int
            let type: String
            let content: String
            let image_urls: String
        }
        let body = try JSONEncoder().encode(Body(spot_id: spotId, type: type, content: content, image_urls: ""))
        let _: EmptyData = try await APIClient.shared.request(
            path: "complaint/create",
            method: "POST",
            body: body
        )
    }

    static func believeChatLink(believeId: String) async throws -> String? {
        let payload: BelieveChatLink = try await APIClient.shared.request(
            path: "believe/chat_link",
            query: ["believe_id": believeId]
        )
        return payload.resolved
    }
}
