# Circadia

A circadian alignment coach for iOS 17+. It senses your rhythm (HealthKit sleep and daylight), prescribes timed actions (sun, weather and travel aware) and explains the mechanism behind each one. It also checks whether you followed a suggestion and shows what happened next, in your own data.

Wellness tool, not medical advice. All logic is deterministic and on-device. There are no accounts, servers or third-party dependencies.

## Build and run

```bash
xcodegen generate        # regenerates Circadia.xcodeproj from project.yml
open Circadia.xcodeproj
```

Demo data is **on by default in DEBUG**, so everything works in the Simulator. Turn it off in Settings → Data & permissions to use real Apple Health data.

Run the tests (no device needed):

```bash
xcodebuild test -project Circadia.xcodeproj -scheme Circadia -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Manual Xcode setup for a real device

1. **Signing:** Target *Circadia* → Signing & Capabilities → set your Team. Change `PRODUCT_BUNDLE_IDENTIFIER` (`com.circadia.app`) in `project.yml` to one you own, then run `xcodegen generate`.
2. **HealthKit:** the entitlements file already has HealthKit and background delivery. Confirm the *HealthKit* capability shows in Xcode with *Background Delivery* checked. Automatic signing registers it on the App ID.
3. **WeatherKit:** in the Apple Developer portal → Identifiers → your App ID, enable **WeatherKit** under both *Capabilities* and *App Services*. It can take up to about 30 minutes to activate. Until it does, the app falls back to on-device NOAA sun math and shows "cloud cover unknown".
4. **Background modes:** *Background fetch* and the `com.circadia.app.refresh` BGTask identifier are already in Info.plist. Check that Background Modes → Background fetch is ticked. To test, pause in the debugger and run `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.circadia.app.refresh"]`.
5. **Time in daylight** needs an Apple Watch on watchOS 10+. Without one, light suggestions rely on manual "Done" taps and the light score component is omitted (the weights renormalise).

Edit `project.yml` rather than the `.xcodeproj` for build settings, Info.plist keys and entitlements, then re-run `xcodegen generate`.

## Layout

```
Circadia/
  App/            CircadiaApp (DI container, BGTask), AppModel (pipeline coordinator), RootView
  Core/Config/    CircadianConfig.swift: every tunable number
  Core/Models/    Domain types, Recommendation, SwiftData record, AppSettings, ClockMath
  Core/Engines/   SleepSessionBuilder, DayMetricsBuilder, CircadianModel, RecommendationEngine,
                  NotificationPlanner (+ TravelDetector), InsightsEngine
  Core/Services/  HealthDataProviding (+ HealthKit, Mock), SunWeatherService (+ WeatherKit,
                  LocalSolar/NOAA, Fallback, Demo), Location, Notifications, RecommendationStore
  Core/Content/   MechanismLibrary, PayoffContent
  Features/       Onboarding, Today, Trends, Insights, Learn (+ How this is calculated), Settings
  DesignSystem/   Time-of-day theme, CircadianRing, shared components
  Tests/          60 unit tests
```
