<img src=".github/assets/Swifka.svg" alt="Swifka" width="128" align="left" />

<b><font>Swifka</font></b>

A read-focused, lightweight, native macOS Kafka client for monitoring clusters, browsing topics, and tracking consumer lag.

<br clear="all" />

<p align="center">
  <b>⚠️ Swifka is currently under active development. We are aiming for a 1.0 stable release.</b>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/Swifka/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/Swifka?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/Swifka/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/Swifka/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/Swifka?color=blue" alt="License" /></a>
</p>

**Why Swifka exists:** Every existing Kafka client is either Java-based (Offset Explorer, Conduktor) or web-based (AKHQ, Kafdrop, Redpanda Console) — none of them feel at home on macOS. When one of our projects started migrating from Redis to Kafka, we needed a fast, frictionless way to monitor clusters, browse messages, and track consumer lag without spinning up a web app or dealing with clunky Java UIs. So we built a native one.

<p align="center">
  <img src=".github/assets/Swifka_demo.gif" alt="Swifka Demo" width="800" />
</p>

# Features

- Connect to any Kafka-compatible cluster (Kafka, Redpanda, etc.)
- Browse topics, partitions, and messages (UTF-8 / Hex / Base64)
- Monitor consumer groups and lag in real time
- View broker stats and cluster metadata
- All read-only by default — safe to point at production

# Install

```bash
brew install --cask ender-wang/tap/swifka
```

Or download the latest `.dmg` from [Releases](https://github.com/Ender-Wang/Swifka/releases).

# Built With

- SwiftUI + Swift 6.2
- [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) + direct librdkafka C interop
- macOS Keychain for credential storage
- JSON-based i18n (English + Simplified Chinese)

---

# Roadmap

## Milestone 1: MVP Core

✨ **Features**

- [x] Cluster connection management (add/edit/delete, multi-cluster switching, test connection)
- [x] Topic list with partition detail (replicas, leader, ISR, watermarks)
- [x] Message browsing (key, value, timestamp, offset) with UTF-8 / Hex / Base64 display
- [x] Consumer group list with lag display (watermark-based)
- [x] Broker list and basic stats (topic count, partition count)

⚙️ **Settings & Infrastructure**

- [x] Config persistence (JSON) + Keychain for credentials
- [x] Manual + timed refresh (5s / 10s / 30s / 60s)
- [x] Read-only by default, extension points for future write features

🌍 **i18n**

- [x] i18n framework — English + Simplified Chinese (JSON-based, easy to contribute)

## Milestone 2: Dashboards & Visualization

📊 **Features**

- [x] Cluster health overview with production/consumption throughput
- [x] Per-topic lag ranking and total lag display
- [x] Per-partition lag breakdown in consumer group detail panel
- [x] Swift Charts — lag trends, throughput trends
- [x] Per-consumer member lag chart (aggregate partition lag per consumer instance)

🔧 **Enhancements**

- [x] Local database storage (SQLite ~~/ SwiftData~~) with configurable retention
- [x] Historical data browsing with date range filtering and scrollable charts
- [x] Hover-to-inspect tooltips on trend charts with color markers and value ranking
- [x] SQL aggregation + extended time ranges for History mode (1h / 6h / 24h / 7d)
- [x] Paginated message browsing (500 per page)

⚠️ **Health & Alerts**

- [x] ISR health monitoring and alerts
  - [x] Alert: Under-replicated partitions (ISR < replication factor)
  - [x] Alert: Critical ISR level (ISR = 1, single point of failure)
  - [x] Alert: ISR below min.insync.replicas (partition at risk)
  - [x] ISR history graph (track ISR changes over time)
- [x] Desktop notifications (macOS native alerts)

## Milestone 3: Animations & Polish

📊 **Advanced Charts**

- [x] ~~Trends page tab reorganization~~ → Split into Trends (cluster health) + Lag (consumer investigation) pages
- [x] ~~Pinch-to-zoom on History charts for time range drill-down~~ — visible window picker (1m–7d) provides equivalent zoom
- [x] ~~Chart statistics overlay (avg / min / max per series in visible window)~~ — superseded by global Mean/Min/Max aggregation mode
- [x] ~~Timeline gap compression~~ — deferred; data smoothing is a better alternative
- [x] ~~Data smoothing for large time windows~~ — covered by Mean/Min/Max SQL downsampling
- [x] ~~Export chart data as CSV~~ → replaced with Excel (.xlsx) export with per-series sheets

🎨 **UI & Animations**

- [x] Animated line drawing for chart transitions
- [x] ~~Message flow animations and real-time data change effects~~ — per-point interpolation conflicts with SwiftUI Charts' y-axis auto-ranging, causing visual glitches; not worth the complexity
- [x] Trends page loading/mode-switch transitions (Live ↔ History)
- [x] Dark mode optimization
- [x] Broker health dashboard (leader distribution chart + stats cards)

🔧 **Enhancements**

- [x] Menu bar resident mode + keyboard shortcuts
- [ ] Connection manager improvements
  - [ ] Quick connection switcher (keyboard shortcut / menu bar)
  - [ ] Recent connections history
  - [ ] Favorite/pin frequently used clusters
  - [ ] Duplicate/clone connection configs
  - [ ] Connection groups/folders for organization

## Milestone 4: Write Operations & Experiments

✨ **Features**

- [ ] Send test messages, create/delete topics, reset offsets (all opt-in)
- [ ] ~~Docker API integration for local dev environments~~ — users manage Docker externally
- [ ] ~~Failure simulation and recovery monitoring~~ — chaos engineering out of scope for a monitoring tool

⚙️ **Settings & Infrastructure**

- [ ] Permission tiers (Read / Write / Admin / Dangerous) with double confirmation

## Milestone 5: Advanced Features

✨ **Features**

- [ ] Message deserialization
  - [ ] Protobuf decoding (import .proto files)
  - [ ] Avro deserialization (with schema registry integration)
  - [ ] Custom deserializers (plugin system)
- [x] JSON pretty-printing with syntax highlighting
- [ ] Message search/filter
  - [ ] Search by key, value, or timestamp
  - [ ] Time range filter
  - [ ] Keyword search
  - [ ] Regex search within JSON
  - [ ] JSON path search (e.g., `$.user.email`)

📊 **Monitoring**

- [ ] Broker liveness monitoring, consumer activity status

📦 **Release**

- [ ] Logo, screenshots, full README, CONTRIBUTING.md, GitHub Releases

---

# Code Formatting

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) for consistent code style.

## Configuration

Formatting rules are defined in **`.swiftformat`** at the project root. Both Xcode and Cursor (or other editors) use this file when formatting Swift code, so the result is the same everywhere.

The config includes:

- Swift version target (`--swiftversion 6.2`)
- Indentation, line breaks, wrapping
- Rules such as `isEmpty` and `preferFinalClasses`

## Setup for Contributors

**Requirements:**

- macOS 15.7 or later
- Xcode 16.2+ (Swift 6, macOS 15.7 SDK)
- [Homebrew](https://brew.sh)

**Install SwiftFormat (required for Xcode build):**

```bash
brew install swiftformat
```

The Xcode project has a **Run Script** build phase that runs SwiftFormat on the `Swifka` app target before compilation. It uses `/opt/homebrew/bin/swiftformat` (Homebrew on Apple Silicon).

If SwiftFormat is not installed, the script prints a warning and the build continues without formatting.

## Format on Save (Cursor / VS Code)

Configure your editor to use SwiftFormat on save so that Cursor and Xcode stay in sync:

1. Install a SwiftFormat extension (e.g. SwiftFormat for VS Code).
2. Set SwiftFormat path to `/opt/homebrew/bin/swiftformat`.
3. Enable **Format on Save** for Swift files.

Both the editor and Xcode will then use the same `.swiftformat` file.

---

# Localization

Swifka uses a custom JSON-based i18n system. Currently supported:

| Language | File | Status |
|----------|------|--------|
| English | `Resources/Locales/en.json` | Complete |
| Simplified Chinese | `Resources/Locales/zh-Hans.json` | Complete |

## Contributing a Translation

1. Copy `Resources/Locales/en.json`
2. Rename to your language code (e.g. `ja.json`, `ko.json`, `fr.json`, `de.json`)
3. Translate the values (keep the keys as-is)
4. Submit a PR

No code changes needed — the app picks up new locale files automatically.

---

# Star History

<a href="https://star-history.com/#Ender-Wang/Swifka&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/Swifka&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/Swifka&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/Swifka&type=Date" />
 </picture>
</a>

---

# License

Swifka is licensed under the [GNU General Public License v3.0](LICENSE).

# Acknowledgments

Swifka is built on top of these open-source projects:

| Project | License | Description |
|---------|---------|-------------|
| [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) | Apache-2.0 | SSWG-maintained Swift wrapper for librdkafka |
| [librdkafka](https://github.com/confluentinc/librdkafka) | BSD-2-Clause | Industry-standard C library for the Kafka protocol |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | Code formatting tool used in the build pipeline |
