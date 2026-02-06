# Swifka

A read-focused, lightweight, native macOS Kafka client for monitoring clusters, browsing topics, and tracking consumer lag.

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
- [ ] Dark mode optimization
- [ ] Cluster topology and broker status visualization

🔧 **Enhancements**
- [ ] Menu bar resident mode + keyboard shortcuts

### Milestone 4: Write Operations & Experiments

✨ **Features**
- [ ] Send test messages, create/delete topics, reset offsets (all opt-in)
- [ ] Docker API integration for local dev environments
- [ ] Failure simulation and recovery monitoring

⚙️ **Settings & Infrastructure**
- [ ] Permission tiers (Read / Write / Admin / Dangerous) with double confirmation

### Milestone 5: Advanced Features

✨ **Features**
- [ ] Protobuf decoding (import .proto files) + JSON pretty-printing
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

## Logo

Swifka doesn't have a logo yet. If you're a designer (or just have a cool idea), feel free to open an issue or PR with your suggestion. Bonus points if it somehow combines Swift and Kafka.

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
