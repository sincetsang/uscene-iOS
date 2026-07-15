# Vendored SDKs

## RiveRuntime

Linked via `Vendor/RiveRuntime.xcframework` (binary 6.21.1). Used by `LandRewardRiveView`.

Re-download if needed:

```bash
curl -L -o /tmp/RiveRuntime.xcframework.zip \
  "https://github.com/rive-app/rive-ios/releases/download/6.21.1/RiveRuntime.xcframework.zip"
unzip -o /tmp/RiveRuntime.xcframework.zip -d Vendor
```

## Enable Reown AppKit (WalletConnect)

Integration code is ready under `Uscene/Features/Shop/WalletConnect/` (`#if canImport(ReownAppKit)`).
SPM resolve currently pulls **yttrium** binary zips (~500MB) and often fails on unstable networks.

### Manual enable

1. Pre-stage binaries (checksums from yttrium `0.10.57`):

```bash
ART="$HOME/Library/Caches/org.swift.swiftpm/artifacts"
mkdir -p "$ART"
curl -L -o /tmp/libyttrium.xcframework.zip \
  "https://github.com/reown-com/yttrium/releases/download/0.10.57/libyttrium.xcframework.zip"
# expected sha256: 2ca0fd6b700550c7a3600244bf15fefd41962c2f4e2d7aed8fdc8a4bd2e28295
curl -L -o /tmp/libyttrium-utils.xcframework.zip \
  "https://github.com/reown-com/yttrium/releases/download/0.10.57/libyttrium-utils.xcframework.zip"
# expected sha256: 99deb5535802177d96c51de380419868710dd3035342116257d24ddcbb33a381
cp /tmp/libyttrium.xcframework.zip \
  "$ART/https___github_com_reown_com_yttrium_releases_download_0_10_57_libyttrium_xcframework_zip"
cp /tmp/libyttrium-utils.xcframework.zip \
  "$ART/https___github_com_reown_com_yttrium_releases_download_0_10_57_libyttrium_utils_xcframework_zip"
```

2. Uncomment the `reown` package + product dependencies in `project.yml`.
3. `xcodegen generate` then open Xcode / resolve packages.
4. Rebuild — `WalletConnectBootstrap.isSDKLinked` becomes `true`.

## UE Token (FEC) iOS SDK

Vendored at `Vendor/UESDKProject.framework` (static, **device arm64 only**).

- Bridged via `UEPayObjCBridge` + `UEPayBridge`
- Linked with `"OTHER_LDFLAGS[sdk=iphoneos*]" = -ObjC -framework UESDKProject`
- Simulator builds stub the bridge (`isAvailable == false`); FEC pay works on **real devices**

### Merchant config (`AppConfig`)

- Store: `优享派`
- Scheme: `yxhmap` (also in `CFBundleURLTypes` + `LSApplicationQueriesSchemes`)
- Logo: `https://boring-test.web.app/favicon.ico`
- Test API → `registBetaWithLogo`; production → `registWithLogo`

### API surface (`UEApi`)

- `registWithLogo:storeName:Schemes:` / `registBetaWithLogo:...`
- `ueCombinedPayWithPaycode:orderno:target:completion:fail:`
- `handleOpenURL:`
