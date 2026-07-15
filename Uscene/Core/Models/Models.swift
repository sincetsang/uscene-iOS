import Foundation
import CoreLocation

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let data: T?
    let err_msg: String?
}

struct EmptyData: Decodable {}

struct TokenResponse: Codable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
}

struct UserProfile: Codable, Identifiable {
    var id: Int { user?.user_id ?? user?.id ?? 0 }
    let user: AppUser?
    let user_assets: [UserAsset]?
    let user_auths: [UserAuthBinding]?
    let user_stat: [UserStatRow]?
}

struct UserStatRow: Codable, Hashable {
    let followers_count: Int?
    let following_count: Int?
    let likes_count: Int?
}

struct UserAuthBinding: Codable, Identifiable, Hashable {
    var id: String { "\(provider ?? "")-\(external_id ?? UUID().uuidString)" }
    let provider: String?
    let external_id: String?
}

struct AppUser: Codable, Hashable {
    let id: Int?
    let user_id: Int?
    let nickname: String?
    let avatar_url: String?
    let level: Int?
    let invite_code: String?
    let profileDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, user_id, nickname, avatar_url, level, invite_code
        case profileDescription = "description"
    }
}

struct LevelConfig: Codable, Hashable {
    let level: Int?
    let name: String?
    let title: String?
    let image: String?
    let image_url: String?
    let description: String?

    var displayName: String { name ?? title ?? level.map { "Lv.\($0)" } ?? "-" }
    var iconURL: String? { image_url ?? image }
}

struct LevelConfigList: Codable {
    let list: [LevelConfig]?
    let levels: [LevelConfig]?
    let items: [LevelConfig]?

    var all: [LevelConfig] { list ?? levels ?? items ?? [] }
}

struct SpotImage: Codable, Identifiable, Hashable {
    let id: Int?
    let image_url: String?
    let sort_index: Int?
}

struct MapSpot: Codable, Identifiable, Hashable {
    var id: Int { spot_id }
    let latitude: Double
    let longitude: Double
    let spot_id: Int
    let title: String?
    let category: String?
    let category_en: String?
    let category_image: String?
    let landmark_image: String?
    let location: String?
    let is_china: Bool?
    let like_count: Int?
    let checkin_count: Int?
    let owner_avatar: String?
    let owner_username: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct SpotGrid: Codable {
    let latitude: Double?
    let longitude: Double?
    let count: String?
    let type: String?
    let points: [MapSpot]?
}

struct SpotGridResponse: Codable {
    let grids: [SpotGrid]?
}

struct SpotPithyResponse: Codable {
    let total_count: Int?
    let points: [MapSpot]?
}

struct SpotListResponse: Codable {
    let total_count: Int?
    let points: [SpotPoint]?
}

struct SpotDetailPayload: Codable {
    let point: SpotPoint?
    let category: String?
    let category_image: String?
    let liked: Bool?
    let images: [SpotImage]?
    let point_images: [SpotImage]?
    let owner_avatar: String?
    let owner_username: String?
    let distance: Double?
    /// Spot goods from `/spot/detail` (RN field name is `product`).
    let product: [ShopProduct]?
}

struct SpotPoint: Codable, Identifiable, Hashable {
    var id: Int { resolvedId }
    let rawId: Int?
    let spot_id: Int?
    let title: String?
    let title_en: String?
    let title_cn: String?
    let description: String?
    let description_en: String?
    let description_cn: String?
    let landmark_image: String?
    let category: String?
    let category_en: String?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let like_count: Int?
    let comment_count: Int?
    let total_checked_in: Int?
    let owner_id: Int?
    let owner_username: String?
    let owner_avatar: String?
    let liked: Bool?
    let images: [SpotImage]?
    let distance: Double?
    let verification_code: String?
    let telegram_url: String?
    let whatsapp_url: String?
    let believe_url: String?
    let believe_id: String?
    let pcn_url: String?
    let wechat: String?
    let external_url: String?
    /// Nearby list may include `products` / `product` for the first-goods strip.
    let products: [ShopProduct]?
    let product: [ShopProduct]?

    var resolvedId: Int { spot_id ?? rawId ?? 0 }

    var displayTitle: String { title ?? title_en ?? title_cn ?? "Spot" }
    var displayImage: String? { landmark_image ?? images?.first?.image_url }
    var firstProduct: ShopProduct? { (products ?? product)?.first }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case spot_id, title, title_en, title_cn
        case description, description_en, description_cn
        case landmark_image, category, category_en, location
        case latitude, longitude, like_count, comment_count, total_checked_in
        case owner_id, owner_username, owner_avatar, liked, images, distance, verification_code
        case telegram_url, whatsapp_url, believe_url, believe_id, pcn_url, wechat, external_url
        case products, product
    }
}

struct NearbySpotItem: Identifiable, Hashable {
    var id: Int { point.resolvedId }
    let point: SpotPoint

    var displayTitle: String { point.displayTitle }
    var displayImage: String? { point.displayImage }
    var distance: Double? { point.distance }
    var category: String? { point.category }
    var firstProduct: ShopProduct? { point.firstProduct }
}

struct CheckinDetailPayload: Codable {
    let checkin: Checkin?
    let point: SpotPoint?
    let user: AppUser?
    let is_liked: Bool?
    let distance: Double?
}

struct Checkin: Codable, Identifiable, Hashable {
    let id: Int
    let content: String?
    let status: Int?
    let `private`: Bool?
    let created_at: String?
    let check_in_point_id: Int?
    let user_id: Int?
    let images: [SpotImage]?
    let like_count: Int?
    let comment_count: Int?
    let is_liked: Bool?
    let user: AppUser?
}

struct UploadImageResponse: Codable {
    let url: String?
    let image_url: String?

    var resolvedURL: String? { url ?? image_url }
}

struct CategoryItem: Codable, Identifiable, Hashable {
    var id: String { type ?? label ?? UUID().uuidString }
    let type: String?
    let label: String?
    let image_url: String?
    // Backward-compatible aliases if some payloads use old keys
    let name: String?
    let name_en: String?
    let image: String?

    var displayName: String { label ?? name ?? type ?? "Category" }
    var imageURL: String? { image_url ?? image }
    var categoryKey: String { type ?? name_en ?? name ?? "" }
}

struct PresignedUpload: Codable {
    let upload_url: String?
    let file_key: String?
}

struct CreateSpotBody: Encodable {
    var title: String
    var latitude: Double
    var longitude: Double
    var location: String
    var country: String
    var province: String
    var city: String
    var image_urls: [String]
    var category: String
    var check_code: String
    var description: String
    var external_url: String = ""
    var telegram_url: String = ""
    var believe_id: String = ""
    var believe_url: String = ""
    var pcn_url: String = ""
    var whatsapp_url: String = ""
    var wechat: String = ""
}

struct UpdateSpotBody: Encodable {
    var spot_id: Int
    var title: String
    var description: String
    var category: String
    var latitude: Double
    var longitude: Double
    var location: String
    var country: String = ""
    var province: String = ""
    var city: String = ""
    var check_code: String = ""
    var image_urls: [String]
    var delete_image_ids: [Int]
    var external_url: String = ""
    var telegram_url: String = ""
    var believe_id: String = ""
    var believe_url: String = ""
    var pcn_url: String = ""
    var whatsapp_url: String = ""
    var wechat: String = ""
}

struct OTAInfo: Codable, Hashable {
    let version: String?
    let platform: String?
    let force_update: String?
    let download_url: String?
    let release_notes: String?
    let min_version: String?
    let file_size: Int?
    let need_update: Bool?
    let created_at: String?
}

struct AdvertisementItem: Codable, Identifiable, Hashable {
    var id: Int { rawId ?? advertisement_id ?? UUID().hashValue }
    let rawId: Int?
    let advertisement_id: Int?
    let title: String?
    let description: String?
    let reward_amount: Double?
    let reward_currency: String?
    let image_url: String?
    let status: Int?
    let check_in_point_id: Int?
    let start_time: String?
    let end_time: String?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case advertisement_id, title, description, reward_amount, reward_currency
        case image_url, status, check_in_point_id, start_time, end_time
    }
}

struct AdvertisementListResponse: Codable {
    let list: [AdvertisementItem]?
    let advertisements: [AdvertisementItem]?
    let items: [AdvertisementItem]?
    let points: [AdvertisementItem]?

    var all: [AdvertisementItem] {
        list ?? advertisements ?? items ?? points ?? []
    }
}

struct LikedSpotsResponse: Codable {
    let points: [OwnedSpotRow]?
    let list: [OwnedSpotRow]?
    let items: [OwnedSpotRow]?

    var all: [OwnedSpotRow] { points ?? list ?? items ?? [] }
}

struct CheckinFeedResponse: Codable {
    let list: [CheckinFeedItem]?
    let checkins: [CheckinFeedItem]?
    let items: [CheckinFeedItem]?

    var all: [CheckinFeedItem] { list ?? checkins ?? items ?? [] }
}

struct CheckinFeedItem: Codable, Identifiable, Hashable {
    var id: Int { checkin?.id ?? rawId ?? UUID().hashValue }
    let rawId: Int?
    let checkin: Checkin?
    let point: SpotPoint?
    let user: AppUser?
    let distance: Double?
    let is_liked: Bool?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case checkin, point, user, distance, is_liked
    }
}

struct OwnedSpotListResponse: Codable {
    let total_count: Int?
    let points: [OwnedSpotRow]?
}

struct OwnedSpotRow: Codable, Identifiable {
    var id: Int { point?.resolvedId ?? UUID().hashValue }
    let point: SpotPoint?
    let category: String?
    let liked: Bool?
    let images: [SpotImage]?
    let point_images: [SpotImage]?
    let distance: Double?

    var displayTitle: String { point?.displayTitle ?? "Spot" }
    var displayImage: String? {
        point?.landmark_image ?? point_images?.first?.image_url ?? images?.first?.image_url
    }
}

struct VerificationCodeListResponse: Codable {
    let list: [VerificationCode]?
    let codes: [VerificationCode]?
    let items: [VerificationCode]?

    var all: [VerificationCode] { list ?? codes ?? items ?? [] }
}

struct VerificationCode: Codable, Identifiable, Hashable {
    var id: Int { code_id ?? rawId ?? UUID().hashValue }
    let rawId: Int?
    let code_id: Int?
    let code: String?
    let created_at: String?
    let use_time: String?
    let statusValue: FlexibleStatus?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case code_id, code, created_at, use_time
        case statusValue = "status"
    }

    var value: String { code ?? "" }
    var isUsed: Bool { statusValue?.isUsed == true }
}

enum FlexibleStatus: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .string("unknown")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    var isUsed: Bool {
        switch self {
        case .int(let value): return value == 1
        case .string(let value): return value.lowercased() == "used"
        }
    }
}

struct CheckinTag: Codable, Identifiable, Hashable {
    var id: String { resolvedId }
    let rawId: Int?
    let name: String?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case name, tag
    }

    var resolvedId: String {
        if let rawId { return "\(rawId)" }
        return name ?? tag ?? UUID().uuidString
    }

    var displayName: String { name ?? tag ?? "#\(resolvedId)" }
}

struct CheckinCommentListResponse: Codable {
    let list: [CheckinCommentThread]?
    let comments: [CheckinCommentThread]?
    let items: [CheckinCommentThread]?

    var all: [CheckinCommentThread] { list ?? comments ?? items ?? [] }
}

struct CheckinCommentThread: Codable, Identifiable, Hashable {
    var id: Int { comment?.id ?? UUID().hashValue }
    let comment: CheckinComment?
    let replies: [CheckinComment]?
}

struct CheckinComment: Codable, Identifiable, Hashable {
    var id: Int { rawId ?? comment_id ?? UUID().hashValue }
    let rawId: Int?
    let comment_id: Int?
    let content: String?
    let created_at: String?
    let city: String?
    let is_liked: Bool?
    let like_count: Int?
    let user: AppUser?
    let replies: [CheckinComment]?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case comment_id, content, created_at, city, is_liked, like_count, user, replies
    }
}

struct CheckinPublishRestrict: Codable, Hashable {
    let max_publish_count: Int?
    let current_publish_count: Int?
    let is_vip: Bool?
    let can_publish: Bool?

    var remaining: Int {
        max(0, (max_publish_count ?? 0) - (current_publish_count ?? 0))
    }
}

struct SpotAddressPayload: Codable, Hashable {
    let location: String?
    let address: String?
    let area: String?
    let country: String?
    let province: String?
    let city: String?
    let point: SpotPoint?

    var displayAddress: String? {
        location ?? address ?? point?.location
    }

    var displayArea: String? {
        if let area, !area.isEmpty { return area }
        let parts = [country, province, city].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct ProductListResponse: Codable {
    let products: [ShopProduct]?
    let total_count: Int?
}

struct ShopProduct: Codable, Identifiable, Hashable {
    var id: Int { product_id ?? rawId ?? 0 }
    let rawId: Int?
    let product_id: Int?
    let spot_id: Int?
    let name: String?
    let description: String?
    let amount: Double?
    let amount_usd: Double?
    let amount_currency: String?
    let check_code_num: Int?
    let head_img: String?
    let image: String?
    let visited_count: Int?
    let audit_status: Int?
    let is_active: Bool?
    let tags: [ProductTag]?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case product_id, spot_id, name, description, amount, amount_usd, amount_currency
        case check_code_num, head_img, image, visited_count, audit_status, is_active, tags
    }

    var cover: String? { head_img ?? image }

    var displayPrice: String {
        if let usd = amount_usd, usd > 0 {
            let unit = amount_currency?.isEmpty == false ? amount_currency! : "USD"
            return String(format: "$%.2f %@", usd, unit == "USD" ? "" : unit).trimmingCharacters(in: .whitespaces)
        }
        if let amount { return String(format: "%.2f FEC", amount) }
        return "-"
    }
}

struct ChatConversation: Codable, Identifiable, Hashable {
    let id: String
    let title: String?

    enum CodingKeys: String, CodingKey { case id, title }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = UUID().uuidString
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}

struct ChatRecommended: Codable, Identifiable, Hashable {
    var id: String { title ?? UUID().uuidString }
    let title: String?
}

struct ChatMessagePayload: Codable {
    let conversation_id: String?
    let content: String?
}

struct ChatThreadMessage: Codable, Identifiable, Hashable {
    var id: String { "\(role ?? "")-\(content ?? "")-\(UUID().uuidString)" }
    let role: String?
    let content: String?
    let is_user: Bool?
    let created_at: String?

    var isFromUser: Bool {
        if let is_user { return is_user }
        return (role ?? "").lowercased() == "user"
    }
}

struct MessageListResponse: Codable {
    let messages: [InboxMessage]?
    let total: Int?
}

struct InboxMessage: Codable, Identifiable, Hashable {
    var id: String { "\(timestamp ?? "")-\(checkin?.id ?? 0)-\(content ?? "")" }
    let content: String?
    let timestamp: String?
    let message_type: String?
    let user: AppUser?
    let checkin: Checkin?
}

struct UnreadCountResponse: Codable {
    let unread_count: Int?
}
