<p align="center">
  <img src=".github/assets/Swifka.svg" alt="Swifka" width="128" />
</p>

<h1 align="center">Swifka</h1>

<p align="center">
  A read-focused, lightweight, native macOS Kafka client for monitoring clusters, browsing topics, and tracking consumer lag.
</p>

**Why Swifka exists:** Every existing Kafka client is either Java-based (Offset Explorer, Conduktor) or web-based (AKHQ, Kafdrop, Redpanda Console) — none of them feel at home on macOS. When one of our projects started migrating from Redis to Kafka, we needed a fast, frictionless way to monitor clusters, browse messages, and track consumer lag without spinning up a web app or dealing with clunky Java UIs. So we built a native one.

<p align="center">
  <img src=".github/assets/Swifka_demo.gif" alt="Swifka Demo" width="800" />
</p>

## Install

```bash
brew install --cask ender-wang/tap/swifka
```

Or download the latest `.dmg` from [Releases](https://github.com/Ender-Wang/Swifka/releases).

**What it does:**

- Connect to any Kafka-compatible cluster (Kafka, Redpanda, etc.)
- Browse topics, partitions, and messages (UTF-8 / Hex / Base64)
- Monitor consumer groups and lag in real time
- View broker stats and cluster metadata
- All read-only by default — safe to point at production

**Built with:**

- SwiftUI + Swift 6.2
- [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) + direct librdkafka C interop
- macOS Keychain for credential storage
- JSON-based i18n (English + Simplified Chinese)

---

## Roadmap

### Milestone 1: MVP Core

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

### Milestone 2: Dashboards & Visualization

📊 **Features**

- [ ] Cluster health overview with production/consumption throughput
- [ ] Per-topic lag ranking and total lag display
- [ ] Swift Charts — lag trends, throughput trends, partition distribution

🔧 **Enhancements**

- [ ] Local database storage (SQLite / SwiftData) with configurable retention
- [ ] Pagination and virtual lists for large datasets

### Milestone 3: Animations & Polish

🎨 **UI & Animations**

- [ ] Message flow animations and real-time data change effects
- [x] Dark mode optimization
- [ ] Cluster topology and broker status visualization

🔧 **Enhancements**

- [x] Menu bar resident mode + keyboard shortcuts

### Milestone 4: Write Operations & Experiments

✨ **Features**

- [ ] Send test messages, create/delete topics, reset offsets (all opt-in)
- [ ] Docker API integration for local dev environments
- [ ] Failure simulation and recovery monitoring

⚙️ **Settings & Infrastructure**

- [ ] Permission tiers (Read / Write / Admin / Dangerous) with double confirmation

### Milestone 5: Advanced Features

✨ **Features**

- [ ] Protobuf decoding (import .proto files)
- [x] JSON pretty-printing with syntax highlighting
- [ ] Message search/filter (time range, keywords)

📊 **Monitoring**

- [ ] Broker liveness monitoring, consumer activity status

📦 **Release**

- [ ] Logo, screenshots, full README, CONTRIBUTING.md, GitHub Releases

---

## Code Formatting

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) for consistent code style.

### Configuration

Formatting rules are defined in **`.swiftformat`** at the project root. Both Xcode and Cursor (or other editors) use this file when formatting Swift code, so the result is the same everywhere.

The config includes:

- Swift version target (`--swiftversion 6.2`)
- Indentation, line breaks, wrapping
- Rules such as `isEmpty` and `preferFinalClasses`

### Setup for Contributors

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

### Format on Save (Cursor / VS Code)

Configure your editor to use SwiftFormat on save so that Cursor and Xcode stay in sync:

1. Install a SwiftFormat extension (e.g. SwiftFormat for VS Code).
2. Set SwiftFormat path to `/opt/homebrew/bin/swiftformat`.
3. Enable **Format on Save** for Swift files.

Both the editor and Xcode will then use the same `.swiftformat` file.

---

## Localization

Swifka uses a custom JSON-based i18n system. Currently supported:

| Language | File | Status |
|----------|------|--------|
| English | `Resources/Locales/en.json` | Complete |
| Simplified Chinese | `Resources/Locales/zh-Hans.json` | Complete |

### Contributing a Translation

1. Copy `Resources/Locales/en.json`
2. Rename to your language code (e.g. `ja.json`, `ko.json`, `fr.json`, `de.json`)
3. Translate the values (keep the keys as-is)
4. Submit a PR

No code changes needed — the app picks up new locale files automatically.

---

## License

Swifka is licensed under the [GNU General Public License v3.0](LICENSE).

### Acknowledgments

Swifka is built on top of these open-source projects:

| Project | License | Description |
|---------|---------|-------------|
| [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) | Apache-2.0 | SSWG-maintained Swift wrapper for librdkafka |
| [librdkafka](https://github.com/confluentinc/librdkafka) | BSD-2-Clause | Industry-standard C library for the Kafka protocol |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | Code formatting tool used in the build pipeline |
