import Foundation

enum OrderKind: String, Hashable {
    case product
    case code
    case member
}

struct ProductDetail: Codable, Identifiable, Hashable {
    var id: Int { product_id ?? rawId ?? 0 }
    let rawId: Int?
    let product_id: Int?
    let spot_id: Int?
    let name: String?
    let description: String?
    let amount: Double?
    let amount_usd: Double?
    let check_code_num: Int?
    let head_img: String?
    let image: String?
    let images: [SpotImage]?
    let comment_count: Int?
    let visited_count: Int?
    let favorite_count: Int?
    let is_favorite: Bool?
    let owner_id: Int?
    let audit_status: Int?
    let is_active: Bool?
    let spot_title_cn: String?
    let spot_title_en: String?
    let tags: [ProductTag]?
    let wechat: String?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case product_id, spot_id, name, description, amount, amount_usd
        case check_code_num, head_img, image, images, comment_count, visited_count
        case favorite_count, is_favorite, owner_id, audit_status, is_active
        case spot_title_cn, spot_title_en, tags, wechat
    }

    var cover: String? { head_img ?? image ?? images?.first?.image_url }
    var gallery: [String] {
        var urls: [String] = []
        if let images {
            urls.append(contentsOf: images.compactMap(\.image_url))
        }
        if urls.isEmpty, let cover {
            urls.append(cover)
        }
        return urls
    }
    var displayPrice: String {
        if let usd = amount_usd, usd > 0 { return String(format: "$%.2f USDT", usd) }
        if let amount { return String(format: "%.2f FEC", amount) }
        return "-"
    }
}

struct ProductCommentList: Codable {
    let list: [ProductComment]?
}

struct ProductComment: Codable, Identifiable, Hashable {
    var id: Int { rawId ?? UUID().hashValue }
    let rawId: Int?
    let content: String?
    let star: Int?
    let created_at: String?
    let user: AppUser?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case content, star, created_at, user
    }
}

struct CommerceOrder: Codable, Identifiable, Hashable {
    var id: String { "\(resolvedId)" }
    let order_id: Int?
    /// Some list payloads use `id` instead of `order_id`.
    let rawId: Int?
    let status: String?
    let pay_type: String?
    let amount: Double?
    let unit: String?
    let currency: String?
    let product_name: String?
    let product_price: Double?
    let period: Int?
    let expired_at: String?
    let head_img: String?
    let code_num: Int?
    let c_at: String?
    let timestamp: String?
    let is_commented: Bool?
    let refund_status: String?
    let refund_info: RefundInfo?
    let contact_info: OrderContact?
    let product: OrderProductBrief?
    let seller_id: Int?

    var resolvedId: Int { order_id ?? rawId ?? 0 }

    enum CodingKeys: String, CodingKey {
        case order_id
        case rawId = "id"
        case status, pay_type, amount, unit, currency
        case product_name, product_price, period, expired_at, head_img, code_num
        case c_at, timestamp, is_commented, refund_status, refund_info
        case contact_info, product, seller_id
    }

    var displayAmount: String {
        let unitText = unit ?? currency ?? pay_type ?? ""
        if let amount {
            return String(format: "%.4g %@", amount, unitText)
        }
        return "-"
    }

    var resolvedRefundId: Int? {
        if let id = refund_info?.refund_id, id != 0 { return id }
        return nil
    }
}

struct RefundInfo: Codable, Hashable {
    let refund_id: Int?
    let status: String?
    let reason: String?
    let reject_reason: String?
}

struct OrderContact: Codable, Hashable {
    let contact_name: String?
    let contact_phone: String?
    let contact_address: String?
}

struct OrderProductBrief: Codable, Hashable {
    let name: String?
    let image: String?
    let head_img: String?
    let amount: Double?
    let amount_usd: Double?

    var cover: String? { head_img ?? image }
}

struct OrderListResponse: Codable {
    let items: [CommerceOrder]?
    let total: Int?
    let records: [CommerceOrder]?
}

struct MarketplaceOrderRow: Codable, Identifiable, Hashable {
    var id: String {
        if let oid = resolvedOrderId { return "\(oid)" }
        return UUID().uuidString
    }
    let order: CommerceOrder?
    let product: OrderProductBrief?
    let spot: SpotPoint?

    var resolvedOrderId: Int? {
        let value = order?.resolvedId ?? 0
        return value > 0 ? value : nil
    }
}

struct MarketplaceOrderListResponse: Codable {
    let items: [MarketplaceOrderRow]?
    let total: Int?
}

struct PayInfo: Codable, Hashable {
    let order_id: Int?
    let pay_type: String?
    let value: String?
    let contract_address: String?
    let receiving_address: String?
    let paycode: String?
}

struct PayStatus: Codable {
    let status: String?
}

struct MemberPlan: Codable, Identifiable, Hashable {
    var id: Int { rawId ?? UUID().hashValue }
    let rawId: Int?
    let period: Int?
    let usdt_price: Double?
    let fec_price: Double?
    let usdt_origin_price: Double?
    let fec_origin_price: Double?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case period, usdt_price, fec_price, usdt_origin_price, fec_origin_price
    }

    var periodText: String {
        guard let period else { return "-" }
        return "\(period) days"
    }
}

struct MemberInfo: Codable {
    let is_vip: Bool?
    let expire_time: String?
    let expired_at: String?

    var expireText: String? { expire_time ?? expired_at }
}

struct UserAsset: Codable, Hashable {
    let currency: String?
    let balance: String?
    let amount: Double?

    var displayBalance: String {
        if let balance, !balance.isEmpty { return balance }
        if let amount { return String(format: "%.4g", amount) }
        return "0"
    }
}

struct BillListResponse: Codable {
    let bills: [WalletBill]?
}

struct WalletBill: Codable, Identifiable, Hashable {
    var id: String { "\(created_at ?? "")-\(amount_str ?? "")-\(type ?? "")" }
    let type: String?
    let created_at: String?
    let amount_str: String?
}

struct WithdrawLatest: Codable {
    let order_id: Int?
    let withdraw_wallet_address: String?
    let value: String?
    let withdraw_status: String?
}

struct CreateProductOrderBody: Encodable {
    let product_id: Int
    let pay_type: String
    let currency: String
    let num: Int
    let contact_name: String
    let contact_phone: String
    let contact_address: String
}

struct CreateCodeOrderBody: Encodable {
    let product_id: Int
    let pay_type: String
    let currency: String
    let num: Int
}

struct PayMethod: Codable, Identifiable, Hashable {
    var id: String { "\(pay_type ?? "")-\(currency ?? "")-\(name ?? "")" }
    let pay_type: String?
    let currency: String?
    let name: String?
    let icon: String?
    let chain: String?
}

struct PayMethodListResponse: Codable {
    let list: [PayMethod]?
    let methods: [PayMethod]?
    let items: [PayMethod]?

    var all: [PayMethod] { list ?? methods ?? items ?? [] }
}

struct CreateMemberOrderBody: Encodable {
    let member_id: Int
    let pay_type: String
}

struct ProductTag: Codable, Identifiable, Hashable {
    var id: String { mark ?? tag_en ?? tag_cn ?? UUID().uuidString }
    let tag_cn: String?
    let tag_en: String?
    let sort_index: Int?
    let mark: String?

    var displayName: String { tag_en ?? tag_cn ?? mark ?? "Tag" }
}

struct ProductPayment: Codable, Hashable {
    var chain: String
    var currency: String
    var amount: Double
}

struct CreateSellerProductBody: Encodable {
    let spot_id: Int
    let name: String
    let description: String
    let image_urls: [String]
    let tags: [String]
    let payments: [ProductPayment]
}

struct UpdateSellerProductBody: Encodable {
    let product_id: Int
    let name: String
    let description: String
    let image_urls: [String]
    let tags: [String]
    let payments: [ProductPayment]
    let delete_image_ids: [Int]
}

struct UserProductListResponse: Codable {
    let points: [UserProductSpotRow]?
    let products: [ShopProduct]?
    let total: Int?
    let total_count: Int?

    var spotRows: [UserProductSpotRow] { points ?? [] }
    var flatProducts: [ShopProduct] {
        if let products, !products.isEmpty { return products }
        return spotRows.flatMap { $0.products ?? [] }
    }
}

struct UserProductSpotRow: Codable, Identifiable, Hashable {
    var id: Int { spot_id ?? rawId ?? UUID().hashValue }
    let rawId: Int?
    let spot_id: Int?
    let title: String?
    let owner_id: Int?
    let wechat: String?
    let images: [String]?
    let products: [ShopProduct]?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case spot_id, title, owner_id, wechat, images, products
    }

    var cover: String? { images?.first ?? products?.first?.cover }
}

struct UserAddress: Codable, Identifiable, Hashable {
    var id: Int { address_id ?? rawId ?? UUID().hashValue }
    let rawId: Int?
    let address_id: Int?
    let name: String?
    let phone: String?
    let area: String?
    let address: String?
    let is_default: Int?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case address_id, name, phone, area, address, is_default
    }

    var isDefault: Bool { is_default == 1 }

    var fullAddress: String {
        [area, address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var contactLine: String {
        [name, phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct AddressListResponse: Codable {
    let list: [UserAddress]?
    let addresses: [UserAddress]?
    let items: [UserAddress]?

    var all: [UserAddress] { list ?? addresses ?? items ?? [] }
}

struct UpsertAddressBody: Encodable {
    var address_id: Int? = nil
    let name: String
    let phone: String
    let area: String
    let address: String
    let is_default: Int

    enum CodingKeys: String, CodingKey {
        case address_id, name, phone, area, address, is_default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(address_id, forKey: .address_id)
        try container.encode(name, forKey: .name)
        try container.encode(phone, forKey: .phone)
        try container.encode(area, forKey: .area)
        try container.encode(address, forKey: .address)
        try container.encode(is_default, forKey: .is_default)
    }
}

struct OtherUserPayload: Codable, Hashable {
    let user: AppUser?
    let is_followed: Bool?
    let follower_count: Int?
    let following_count: Int?
    let checkin_count: Int?
}

struct FollowResult: Codable, Hashable {
    let is_followed: Bool?
}

struct UserCheckinListResponse: Codable {
    let checkins: [CheckinFeedItem]?
    let list: [CheckinFeedItem]?
    let items: [CheckinFeedItem]?

    var all: [CheckinFeedItem] { checkins ?? list ?? items ?? [] }
}

struct ComplaintType: Codable, Identifiable, Hashable {
    var id: String { type ?? label ?? UUID().uuidString }
    let type: String?
    let label: String?
    let name: String?

    var displayName: String { label ?? name ?? type ?? "Type" }
}

struct BelieveChatLink: Codable {
    let url: String?
    let chat_link: String?
    let believe_url: String?

    var resolved: String? { url ?? chat_link ?? believe_url }
}

struct UserStatistics: Codable, Hashable {
    let total_spot: Int?
    let total_spot_liked: Int?
    let total_product: Int?
    let total_product_visited: Int?
    let total_product_favorited: Int?
    let total_product_sold: Int?
    let total_product_bought: Int?
    let total_product_pending_comment: Int?
    let total_verify_code: Int?
    let total_verify_code_order: Int?
}

struct InviteInfo: Codable, Hashable {
    let invite_code: String?
    let invite_count: Int?
    let invite_url: String?
    let code: String?

    var resolvedCode: String? { invite_code ?? code }
}

struct PremiumInfo: Codable, Hashable {
    let is_premium: Bool?
    let is_vip: Bool?
    let expired_at: String?
    let level: Int?
}
