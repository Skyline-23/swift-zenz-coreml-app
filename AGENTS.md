# Repository Guidelines

## Project Structure & Module Organization
- `swift-zenz-coreml-app/` contains the SwiftUI entry points (`swift_zenz_coreml_appApp.swift`, `ContentView.swift`) plus `swift_zenz_coreml.swift`, which owns Core ML inference, tokenizer wiring, and log helpers.
- `Resources/` stores the `zenz_v1*.mlpackage` artifacts, tokenizer assets, and conversion scripts; keep new assets here so `Bundle.main.resourceURL` continues to resolve them.
- Tests live in `swift-zenz-coreml-appTests/` (Swift Testing) and `swift-zenz-coreml-appUITests/` (XCTest), while device notes belong under `benchmarks/`.

## Build, Test, and Development Commands
- `xed swift-zenz-coreml-app.xcodeproj` opens the project in Xcode.
- `xcodebuild -project swift-zenz-coreml-app.xcodeproj -scheme swift-zenz-coreml-app -destination 'platform=iOS Simulator,name=iPhone 15' build` performs a CI-friendly build.
- `xcodebuild -project swift-zenz-coreml-app.xcodeproj -scheme swift-zenz-coreml-app -destination 'platform=iOS Simulator,name=iPhone 15' test` runs unit and UI suites; reuse your simulator destination.
- Set `GenerationLogConfig.enableVerbose = true` in debug builds when you need detailed benchmark logging.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines: 4-space indentation, `PascalCase` types, `camelCase` functions/properties, and reserve `SCREAMING_SNAKE_CASE` for bridging constants.
- Preserve multilingual doc blocks (🇯🇵/🇰🇷/🇺🇸) in files like `swift_zenz_coreml.swift` and add a short English summary when introducing new notes.
- Prefer `struct` + extensions for helpers, co-locate Core ML utilities with tokenizer code, and format via Xcode’s “Re-Indent” or `swift-format --recursive swift-zenz-coreml-app`.

## Testing Guidelines
- Unit tests rely on Swift Testing; declare cases as `@Test func testScenario_expectation()` and mark async UI code with `@MainActor`.
- UI suites extend `XCTestCase`, launch via `XCUIApplication()`, and may attach `XCTApplicationLaunchMetric` when measuring performance.
- Keep inference helpers at ≥80% coverage, add regression cases whenever tokenizer behavior or rankings change, and rerun `xcodebuild -project swift-zenz-coreml-app.xcodeproj -scheme swift-zenz-coreml-app -destination 'platform=iOS Simulator,name=iPhone 15' test` before pushing.

## Commit & Pull Request Guidelines
- Match the current Git history: short, imperative subjects (“Fix textview”, “Standardize time range notation”) with optional body detail.
- Reference issues or benchmark rounds in commit bodies (`Refs #123`) and mention affected devices whenever performance numbers change.
- PRs should describe UI impact, include screenshots for UI tweaks, list the commands you ran, and summarize any `Resources/` deltas.

## Model & Resource Handling
- Keep `.mlpackage` files, tokenizer vocabularies, and conversion scripts inside `Resources/`; do not scatter experiments elsewhere.
- Document tweaks to `convert-to-CoreML*.py` in `Resources/README.md` so the pipeline stays reproducible.
- Coordinate tokenizer updates with the upstream `zenz-CoreML` repo; mismatches crash before inference, so treat the vocab as immutable unless it is synced.
