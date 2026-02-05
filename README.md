# Swifka

A read-focused, lightweight, native macOS Kafka client for monitoring clusters, browsing topics, and tracking consumer lag.

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
