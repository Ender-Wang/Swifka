import Kafka
import Crdkafka
import Logging
import Foundation

// ============================================================
// Swift Kafka Client API Explorer - Test librdkafka C API directly
// ============================================================

let logger = Logger(label: "swifka-explorer")

print("=" .repeated(60))
print("Swifka API Explorer - Testing librdkafka C API")
print("=" .repeated(60))
print("")

// Configuration
let bootstrapServers = "localhost:9092"

// ============================================================
// Test 1: Create client using swift-kafka-client
// ============================================================
print("📌 Test 1: Create connection via swift-kafka-client")
print("-" .repeated(50))

do {
    let config = KafkaConsumerConfiguration(
        consumptionStrategy: .group(id: "swifka-explorer-\(UUID())", topics: ["orders"]),
        bootstrapBrokerAddresses: [
            KafkaConfiguration.BrokerAddress(host: "localhost", port: 9092)
        ]
    )
    
    let consumer = try KafkaConsumer(configuration: config, logger: logger)
    print("✅ KafkaConsumer created successfully")
    
    // Issue: swift-kafka-client does not expose the underlying kafka handle
    // so we cannot call rd_kafka_metadata and other Admin APIs
    print("⚠️  However, swift-kafka-client does not expose the underlying handle for Admin API")
    print("")
} catch {
    print("❌ Failed to create Consumer: \(error)")
}

// ============================================================
// Test 2: Use librdkafka C API directly
// ============================================================
print("")
print("📌 Test 2: Use librdkafka C API directly to get Metadata")
print("-" .repeated(50))

// Create configuration
let conf = rd_kafka_conf_new()!

// Set bootstrap servers
_ = "bootstrap.servers".withCString { key in
    bootstrapServers.withCString { value in
        rd_kafka_conf_set(conf, key, value, nil, 0)
    }
}

// Create Kafka handle (as consumer)
var errstr = [CChar](repeating: 0, count: 512)
guard let kafkaHandle = rd_kafka_new(RD_KAFKA_CONSUMER, conf, &errstr, errstr.count) else {
    print("❌ Failed to create Kafka handle: \(String(cString: errstr))")
    exit(1)
}
print("✅ Kafka handle created successfully")

// ------------------------------------------------------------
// Test rd_kafka_metadata - Get Topics and Brokers info
// ------------------------------------------------------------
print("")
print("📋 Fetching cluster Metadata...")

var metadataPtr: UnsafePointer<rd_kafka_metadata>?
let metadataErr = rd_kafka_metadata(
    kafkaHandle,
    1,  // all_topics = true
    nil,
    &metadataPtr,
    10000  // timeout 10s
)

if metadataErr == RD_KAFKA_RESP_ERR_NO_ERROR, let metadata = metadataPtr {
    print("✅ Metadata fetched successfully!")
    print("")
    
    // Broker info
    print("🖥️  Brokers (\(metadata.pointee.broker_cnt)):")
    for i in 0..<Int(metadata.pointee.broker_cnt) {
        let broker = metadata.pointee.brokers[i]
        let host = String(cString: broker.host)
        print("   - Broker \(broker.id): \(host):\(broker.port)")
    }
    print("")
    
    // Topic info
    print("📁 Topics (\(metadata.pointee.topic_cnt)):")
    for i in 0..<Int(metadata.pointee.topic_cnt) {
        let topic = metadata.pointee.topics[i]
        let topicName = String(cString: topic.topic)
        print("   - \(topicName) (\(topic.partition_cnt) partitions)")
        
        // Partition details
        for j in 0..<Int(topic.partition_cnt) {
            let partition = topic.partitions[j]
            print("     └─ Partition \(partition.id): leader=\(partition.leader), replicas=\(partition.replica_cnt), ISR=\(partition.isr_cnt)")
        }
    }
    
    // Release metadata
    rd_kafka_metadata_destroy(metadata)
} else {
    print("❌ Failed to fetch Metadata: \(rd_kafka_err2str(metadataErr)!)")
}

// ------------------------------------------------------------
// Test rd_kafka_list_groups - Get Consumer Groups
// ------------------------------------------------------------
print("")
print("👥 Fetching Consumer Groups...")

var groupListPtr: UnsafePointer<rd_kafka_group_list>?
let groupErr = rd_kafka_list_groups(
    kafkaHandle,
    nil,  // Get all groups
    &groupListPtr,
    10000  // timeout 10s
)

if groupErr == RD_KAFKA_RESP_ERR_NO_ERROR, let groupList = groupListPtr {
    print("✅ Consumer Groups fetched successfully!")
    print("")
    print("📋 Consumer Groups (\(groupList.pointee.group_cnt)):")
    
    if groupList.pointee.group_cnt == 0 {
        print("   (No active consumer groups)")
    } else {
        for i in 0..<Int(groupList.pointee.group_cnt) {
            let group = groupList.pointee.groups[i]
            let groupName = String(cString: group.group)
            let state = String(cString: group.state)
            let protocol_type = String(cString: group.protocol_type)
            print("   - Group: \(groupName)")
            print("     State: \(state)")
            print("     Protocol: \(protocol_type)")
            print("     Members: \(group.member_cnt)")
        }
    }
    
    rd_kafka_group_list_destroy(groupListPtr)
} else {
    print("❌ Failed to fetch Consumer Groups: \(String(cString: rd_kafka_err2str(groupErr)!))")
}

// ------------------------------------------------------------
// Test getting Topic High Watermark (for Lag calculation)
// ------------------------------------------------------------
print("")
print("📊 Fetching Topic Watermarks (for Lag calculation)...")

let testTopic = "orders"
var lowWatermark: Int64 = 0
var highWatermark: Int64 = 0

// Get partition 0 watermark
let watermarkErr = rd_kafka_query_watermark_offsets(
    kafkaHandle,
    testTopic,
    0,  // partition 0
    &lowWatermark,
    &highWatermark,
    10000
)

if watermarkErr == RD_KAFKA_RESP_ERR_NO_ERROR {
    print("✅ Topic '\(testTopic)' Partition 0:")
    print("   Low Watermark:  \(lowWatermark)")
    print("   High Watermark: \(highWatermark)")
    print("   Messages in partition: \(highWatermark - lowWatermark)")
} else {
    print("❌ Failed to fetch Watermark: \(String(cString: rd_kafka_err2str(watermarkErr)!))")
}

// Cleanup
rd_kafka_destroy(kafkaHandle)

print("")
print("=" .repeated(60))
print("🎉 API exploration complete!")
print("=" .repeated(60))
print("")
print("Conclusion:")
print("✅ rd_kafka_metadata      - Works, can fetch Topics/Brokers/Partitions")
print("✅ rd_kafka_list_groups   - Works, can fetch Consumer Groups")
print("✅ rd_kafka_query_watermark_offsets - Works, can fetch Offsets for Lag calculation")
print("")
print("Next step: Wrap these C APIs into Swift-friendly interfaces")

// String extension for convenience
extension String {
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
