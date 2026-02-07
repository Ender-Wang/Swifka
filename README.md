# Swifka API Verification (POC)

This document summarizes the proof-of-concept work to verify that we can build a native macOS Kafka monitoring client using Swift.

## Objective

Verify that Swift can access the necessary Kafka APIs for:
1. Listing topics, brokers, and partitions
2. Listing consumer groups
3. Getting offsets for lag calculation
4. Consuming messages for browsing

## Technology Stack

| Component | Choice | Notes |
|-----------|--------|-------|
| Kafka Library | [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) | SSWG maintained, wraps librdkafka |
| Underlying C Library | librdkafka | Industry standard, bundled with swift-kafka-client |
| Test Environment | Redpanda | Kafka-compatible, lightweight, single container |

## Findings

### swift-kafka-client Coverage

The library provides high-level Swift APIs for:
- ✅ `KafkaProducer` - Producing messages
- ✅ `KafkaConsumer` - Consuming messages with AsyncSequence
- ✅ Consumer group subscription
- ✅ Manual offset commits
- ✅ TLS/SASL authentication
- ✅ Basic statistics (throughput metrics)

**Not provided** (but available in underlying librdkafka):
- ❌ Metadata API (topic/broker/partition listing)
- ❌ Consumer group listing
- ❌ Consumer group offset queries (for lag calculation)
- ❌ Admin operations (create/delete topics)

### Direct librdkafka C API Access

We verified that Swift can directly call librdkafka C APIs via `import Crdkafka`:

| API | Status | Purpose |
|-----|--------|---------|
| `rd_kafka_metadata()` | ✅ Works | Get topics, brokers, partitions |
| `rd_kafka_list_groups()` | ✅ Works | List consumer groups |
| `rd_kafka_query_watermark_offsets()` | ✅ Works | Get high/low watermarks for lag |

### Test Results

```
📋 Fetching cluster Metadata...
✅ Metadata fetched successfully!

🖥️  Brokers (1):
   - Broker 0: localhost:9092

📁 Topics (4):
   - orders (3 partitions)
   - users (2 partitions)
   - logs (1 partitions)
   - __consumer_offsets (3 partitions)

👥 Fetching Consumer Groups...
✅ Consumer Groups fetched successfully!

📊 Fetching Topic Watermarks (for Lag calculation)...
✅ Topic 'orders' Partition 0:
   Low Watermark:  0
   High Watermark: 2
   Messages in partition: 2
```

## Architecture Decision

Based on the POC results, the recommended architecture:

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Layer                     │
│  (Views, ViewModels - @MainActor)                   │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                  KafkaService                        │
│  (Actor - isolates Kafka operations)                │
└─────────────────────────────────────────────────────┘
                         │
           ┌─────────────┴─────────────┐
           ▼                           ▼
┌───────────────────┐       ┌───────────────────────┐
│ swift-kafka-client│       │ librdkafka (direct)   │
│  - Consumer       │       │  - Metadata API       │
│  - Producer       │       │  - List Groups        │
│                   │       │  - Watermark Offsets  │
└───────────────────┘       └───────────────────────┘
```

## Running the POC

### Prerequisites

- Docker
- Xcode / Swift toolchain
- OpenSSL (`brew install openssl@3`)

### Start Kafka (Redpanda)

```bash
docker-compose up -d
```

This creates:
- Redpanda broker at `localhost:9092`
- Test topics: `orders` (3 partitions), `users` (2 partitions), `logs` (1 partition)
- Sample messages in each topic

### Run the Explorer

```bash
swift run SwifkaExplorer
```

### Cleanup

```bash
docker-compose down -v
```

## Conclusion

**The project is technically feasible.**

- Message browsing: Use `swift-kafka-client`'s `KafkaConsumer`
- Metadata/monitoring: Directly call librdkafka C APIs
- The C interop is straightforward and works reliably
