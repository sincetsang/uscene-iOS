# UsceneNative – signing / project generate

- Do **not** change `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, or other signing fields in `project.yml` / `project.pbxproj`.
- Do **not** run `xcodegen generate` unless the user explicitly asks — it regenerates the Xcode project and **clears the Development Team** set in Xcode Signing & Capabilities.
- Prefer Swift/plist edits + `xcodebuild`. For new source files without xcodegen, ask the user to add the file in Xcode (or approve a one-time generate).
