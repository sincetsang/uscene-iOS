# Uscene Native (SwiftUI)

Pure SwiftUI iOS app ported from the React Native / Expo Uscene client.

**UI aligns with the RN Expo layouts** (custom tab bar, map chrome, UAI / Shop / Mine shells). **Map engine remains MapKit** (RN uses Google Maps; we do not ship GMS).

## Requirements

- macOS + Xcode 15+
- iOS 17+ simulator or device

## Open / build

```bash
cd ~/Desktop/UsceneNative
xcodegen generate   # if project.yml changed
open UsceneNative.xcodeproj
```

Or from CLI:

```bash
xcodebuild -project UsceneNative.xcodeproj -scheme Uscene -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Phase 1 scope

- Map tab (MapKit) + nearby / search
- Landmark detail + album
- Email OTP + Sign in with Apple / Google
- Create / view check-in (photo upload, like, comment)
- Mine + language settings (en / zh / zh_tw)
- API logger (console + in-app)
- API: `https://api.test.uscene.ebunker.io`

## Phase 2 scope

- 4 tabs: Map / U AI / Shop / Mine
- Shop product list
- U AI recommended prompts + conversations + chat send
- Create landmark (photos, category, map pin, check code)
- My landmarks list
- Messages inbox
- Profile nickname update

## Phase 3 scope

- Product detail + favorite + comments
- Create marketplace order (USDT pay_type) + order detail with receiving address / polling
- My Buy / My Sell / Code orders
- VIP plans + VIP orders
- USDT / FEC wallet bills; USDT withdraw
- Deferred: WalletConnect transfer, UE/FEC native pay SDK

## Phase 4 scope

- Edit landmark (`spot/update`) from owner detail / my landmarks
- Landmark like + favorites collection (`spot/like`, `spot/like/list`)
- Check-in feed (map + mine + per-spot)
- Ads / rewards list + claim (no Rive)
- OTA check in Settings (`ota/latest`)

## Phase 5 scope

- My products + create/edit/publish/unpublish
- Shipping address book + checkout address picker
- Product favorites + browsing history
- Shop product keyword search

## Phase 6 scope

- Order refunds (apply / approve / reject), seller cancel, update price/address, delete
- Buy/Sell list refund filter
- Other user profile + follow + check-ins
- Landmark contacts (TG / WhatsApp / WeChat / Believe / P.CN / website) + report
- Privacy policy WebView (login + settings)

## Phase 7 scope

- Product order reviews (pending list + write/edit from order detail)
- Profile avatar upload + bio + invite code
- Mine statistics overview + premium badge
- Check-in delete + private toggle (owner)

## Phase 8 scope

- Buy/Sell order status menu filters
- USDT pay: open MetaMask deep link + share pay info (no WalletConnect SDK)
- Landmark license card + create-product shortcut for owners

## Phase 9 scope

- Verification code inventory (all / unused / used) + copy
- Buy verification-code packages (v2 `order/create`) with qty + USDT/FEC
- Marketplace checkout quantity + currency picker
- Check-in comment threads (list / reply / like / delete)
- Create check-in private toggle + tags
- Landmark directions via Apple Maps

## Phase 10 scope

- Check-in publish quota + VIP upsell; landmark picker while creating
- Landmark reviews (`spot/comment/list`) + Latest/Recommended check-ins
- Map category chips + unified spot/product search tabs
- Address map picker; code-order cancel; FEC withdraw + pay labels
- Mine: create check-in / my check-ins + invite share

## Phase 11 scope

- Login invite code; linked accounts + level badge on profile/Mine
- Lat/lng heartbeat when logged in; landmark country/province/city + Believe URL resolve
- U AI city context + Markdown replies; launch OTA prompt; map message/check-in FABs
- Check-in feed pagination

## Phase 12 — SDK integration

- **WalletConnect / Reown AppKit**: pay path implemented (`CryptoPayService` / Order Detail). SPM package temporarily commented in `project.yml` until yttrium binaries (~500MB) download — see **Vendor/README.md → Enable Reown AppKit**. Code uses `#if canImport(ReownAppKit)`.
- **Rive**: vendored `Vendor/RiveRuntime.xcframework` (6.21.1); reward sheet after ad claim (`LandRewardRiveView` + `land.riv`)
- **UE Pay**: runtime bridge in `UEPayBridge` + drop-in steps in `Vendor/README.md` (iOS XCFramework not shipped by Expo; FEC button shows until linked)

## Phase 13 — RN UI fidelity

- Custom tab bar (`MainTabBar`) matching Expo `CustomTabBar` (colors `#007BFE` / `#24302C`, RN icons)
- Map chrome on **MapKit**: FABs, center check-in CTA, bottom sheet + topic chips, category-colored markers (no Google Maps SDK)
- U AI / Shop / Mine home shells aligned to RN layouts (`uai.tsx` / `shop.tsx` / `mine/index.tsx`)
- Design tokens in `Uscene/Design/Theme.swift`; assets imported from RN under `Assets.xcassets`

## Later / polish

- China map pin GCJ offset
- UE Pay full flow once vendor iOS XCFramework is linked
- WalletConnect receipt polling refinements
- Next-level pixel polish on secondary screens (detail pages)