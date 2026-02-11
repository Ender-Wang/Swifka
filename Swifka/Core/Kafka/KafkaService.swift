import Crdkafka
import Foundation
import Kafka

/// Wrapper to send OpaquePointer across isolation boundaries.
/// librdkafka handles are thread-safe for concurrent operations, so this is sound.
private nonisolated struct SendableHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

actor KafkaService {
    private var handle: OpaquePointer?
    private let stringSize = 512
    /// Serial queue ensures rd_kafka_destroy() never runs while other C calls are in-flight
    private static let blockingQueue = DispatchQueue(label: "com.swifka.kafka-blocking")

    /// Run a blocking C call on a background queue so the actor executor is freed.
    /// This allows other actor methods (e.g. disconnect) to execute while the C call blocks.
    private nonisolated static func offload<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T,
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            blockingQueue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    var isConnected: Bool {
        handle != nil
    }

    // MARK: - Connection

    func connect(config: ClusterConfig, password: String? = nil) throws {
        disconnect()

        let conf = rd_kafka_conf_new()!

        try setConfig(conf, key: "bootstrap.servers", value: config.bootstrapServers)
        try setConfig(conf, key: "client.id", value: "swifka-monitor")

        if config.authType == .sasl, let mechanism = config.saslMechanism {
            try setConfig(conf, key: "security.protocol", value: config.useTLS ? "sasl_ssl" : "sasl_plaintext")
            try setConfig(conf, key: "sasl.mechanism", value: mechanism.rawValue)
            if let username = config.saslUsername {
                try setConfig(conf, key: "sasl.username", value: username)
            }
            if let password {
                try setConfig(conf, key: "sasl.password", value: password)
            }
        } else if config.useTLS {
            try setConfig(conf, key: "security.protocol", value: "ssl")
        }

        let errorChars = UnsafeMutablePointer<CChar>.allocate(capacity: stringSize)
        defer { errorChars.deallocate() }

        guard let kafkaHandle = rd_kafka_new(RD_KAFKA_CONSUMER, conf, errorChars, stringSize) else {
            let errorString = String(cString: errorChars)
            throw SwifkaError.connectionFailed(errorString)
        }

        handle = kafkaHandle
    }

    func disconnect() {
        guard let oldHandle = handle else { return }
        handle = nil
        // Destroy on serial queue so it waits for any in-flight C calls to finish first
        let h = SendableHandle(pointer: oldHandle)
        Self.blockingQueue.async {
            rd_kafka_destroy(h.pointer)
        }
    }

    func testConnection(config: ClusterConfig, password: String? = nil) throws -> Bool {
        let testConf = rd_kafka_conf_new()!

        try setConfig(testConf, key: "bootstrap.servers", value: config.bootstrapServers)
        try setConfig(testConf, key: "client.id", value: "swifka-test")

        if config.authType == .sasl, let mechanism = config.saslMechanism {
            try setConfig(testConf, key: "security.protocol", value: config.useTLS ? "sasl_ssl" : "sasl_plaintext")
            try setConfig(testConf, key: "sasl.mechanism", value: mechanism.rawValue)
            if let username = config.saslUsername {
                try setConfig(testConf, key: "sasl.username", value: username)
            }
            if let password {
                try setConfig(testConf, key: "sasl.password", value: password)
            }
        } else if config.useTLS {
            try setConfig(testConf, key: "security.protocol", value: "ssl")
        }

        let errorChars = UnsafeMutablePointer<CChar>.allocate(capacity: stringSize)
        defer { errorChars.deallocate() }

        guard let testHandle = rd_kafka_new(RD_KAFKA_CONSUMER, testConf, errorChars, stringSize) else {
            let errorString = String(cString: errorChars)
            throw SwifkaError.connectionFailed(errorString)
        }
        defer { rd_kafka_destroy(testHandle) }

        var metadataPtr: UnsafePointer<rd_kafka_metadata_t>?
        let result = rd_kafka_metadata(testHandle, 1, nil, &metadataPtr, Constants.kafkaTimeout)
        defer { if let metadataPtr { rd_kafka_metadata_destroy(metadataPtr) } }

        guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
            let errStr = String(cString: rd_kafka_err2str(result))
            throw SwifkaError.connectionFailed(errStr)
        }

        return true
    }

    // MARK: - Metadata

    func fetchMetadata() async throws -> (brokers: [BrokerInfo], topics: [TopicInfo]) {
        guard let handle else {
            throw SwifkaError.notConnected
        }
        let h = SendableHandle(pointer: handle)
        let timeout = Constants.kafkaTimeout

        return try await Self.offload {
            var metadataPtr: UnsafePointer<rd_kafka_metadata_t>?
            let result = rd_kafka_metadata(h.pointer, 1, nil, &metadataPtr, timeout)

            guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
                let errStr = String(cString: rd_kafka_err2str(result))
                throw SwifkaError.metadataFailed(errStr)
            }

            guard let metadata = metadataPtr?.pointee else {
                throw SwifkaError.metadataFailed("Null metadata pointer")
            }
            defer { rd_kafka_metadata_destroy(metadataPtr) }

            // Parse brokers
            var brokers: [BrokerInfo] = []
            for i in 0 ..< Int(metadata.broker_cnt) {
                let broker = metadata.brokers[i]
                brokers.append(BrokerInfo(
                    id: broker.id,
                    host: String(cString: broker.host),
                    port: Int32(broker.port),
                ))
            }

            // Parse topics
            var topics: [TopicInfo] = []
            for i in 0 ..< Int(metadata.topic_cnt) {
                let topic = metadata.topics[i]
                let topicName = String(cString: topic.topic)

                var partitions: [PartitionInfo] = []
                for j in 0 ..< Int(topic.partition_cnt) {
                    let partition = topic.partitions[j]

                    var replicas: [Int32] = []
                    for r in 0 ..< Int(partition.replica_cnt) {
                        replicas.append(partition.replicas[r])
                    }

                    var isrs: [Int32] = []
                    for s in 0 ..< Int(partition.isr_cnt) {
                        isrs.append(partition.isrs[s])
                    }

                    partitions.append(PartitionInfo(
                        partitionId: partition.id,
                        leader: partition.leader,
                        replicas: replicas,
                        isr: isrs,
                    ))
                }

                topics.append(TopicInfo(
                    name: topicName,
                    partitions: partitions,
                ))
            }

            return (brokers, topics)
        }
    }

    // MARK: - Watermarks

    func fetchWatermarks(topic: String, partition: Int32) async throws -> (low: Int64, high: Int64) {
        guard let handle else {
            throw SwifkaError.notConnected
        }
        let h = SendableHandle(pointer: handle)
        let timeout = Constants.kafkaTimeout

        return try await Self.offload {
            var low: Int64 = 0
            var high: Int64 = 0

            let result = rd_kafka_query_watermark_offsets(
                h.pointer,
                topic,
                partition,
                &low,
                &high,
                timeout,
            )

            guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
                let errStr = String(cString: rd_kafka_err2str(result))
                throw SwifkaError.watermarkFailed(errStr)
            }

            return (low, high)
        }
    }

    func fetchAllWatermarks(topics: [TopicInfo]) async -> [TopicInfo] {
        var result: [TopicInfo] = []
        for topic in topics {
            var updatedPartitions = topic.partitions
            for i in updatedPartitions.indices {
                let partition = updatedPartitions[i]
                if let watermarks = try? await fetchWatermarks(
                    topic: topic.name,
                    partition: partition.partitionId,
                ) {
                    updatedPartitions[i] = PartitionInfo(
                        partitionId: partition.partitionId,
                        leader: partition.leader,
                        replicas: partition.replicas,
                        isr: partition.isr,
                        lowWatermark: watermarks.low,
                        highWatermark: watermarks.high,
                    )
                }
            }
            result.append(TopicInfo(name: topic.name, partitions: updatedPartitions))
        }
        return result
    }

    // MARK: - Consumer Groups

    func fetchConsumerGroups() async throws -> [ConsumerGroupInfo] {
        guard let handle else {
            throw SwifkaError.notConnected
        }
        let h = SendableHandle(pointer: handle)
        let timeout = Constants.kafkaTimeout

        return try await Self.offload {
            var groupListPtr: UnsafePointer<rd_kafka_group_list>?
            let result = rd_kafka_list_groups(h.pointer, nil, &groupListPtr, timeout)

            guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
                let errStr = String(cString: rd_kafka_err2str(result))
                throw SwifkaError.consumerGroupsFailed(errStr)
            }

            guard let groupList = groupListPtr?.pointee else {
                throw SwifkaError.consumerGroupsFailed("Null group list pointer")
            }
            defer { rd_kafka_group_list_destroy(groupListPtr) }

            var groups: [ConsumerGroupInfo] = []
            for i in 0 ..< Int(groupList.group_cnt) {
                let group = groupList.groups[i]

                var members: [GroupMemberInfo] = []
                for j in 0 ..< Int(group.member_cnt) {
                    let member = group.members[j]
                    members.append(GroupMemberInfo(
                        memberId: String(cString: member.member_id),
                        clientId: String(cString: member.client_id),
                        clientHost: String(cString: member.client_host),
                    ))
                }

                groups.append(ConsumerGroupInfo(
                    name: String(cString: group.group),
                    state: String(cString: group.state),
                    protocolType: String(cString: group.protocol_type),
                    protocol: String(cString: group.protocol),
                    members: members,
                ))
            }

            return groups
        }
    }

    // MARK: - Message Browsing

    func browseMessages(
        config: ClusterConfig,
        topic: String,
        partition: Int32?,
        maxMessages: Int = Constants.defaultMaxMessages,
        password: String? = nil,
    ) throws -> [KafkaMessageRecord] {
        // Create a separate consumer with a random group ID to avoid affecting business consumers
        let consumerConf = rd_kafka_conf_new()!
        let groupId = "swifka-browse-\(UUID().uuidString.prefix(8))"

        try setConfig(consumerConf, key: "bootstrap.servers", value: config.bootstrapServers)
        try setConfig(consumerConf, key: "group.id", value: groupId)
        try setConfig(consumerConf, key: "auto.offset.reset", value: "earliest")
        try setConfig(consumerConf, key: "enable.auto.commit", value: "false")
        try setConfig(consumerConf, key: "enable.partition.eof", value: "true")
        try setConfig(consumerConf, key: "client.id", value: "swifka-browser")

        if config.authType == .sasl, let mechanism = config.saslMechanism {
            try setConfig(consumerConf, key: "security.protocol", value: config.useTLS ? "sasl_ssl" : "sasl_plaintext")
            try setConfig(consumerConf, key: "sasl.mechanism", value: mechanism.rawValue)
            if let username = config.saslUsername {
                try setConfig(consumerConf, key: "sasl.username", value: username)
            }
            if let password {
                try setConfig(consumerConf, key: "sasl.password", value: password)
            }
        } else if config.useTLS {
            try setConfig(consumerConf, key: "security.protocol", value: "ssl")
        }

        let errorChars = UnsafeMutablePointer<CChar>.allocate(capacity: stringSize)
        defer { errorChars.deallocate() }

        guard let consumer = rd_kafka_new(RD_KAFKA_CONSUMER, consumerConf, errorChars, stringSize) else {
            let errorString = String(cString: errorChars)
            throw SwifkaError.messageFetchFailed(errorString)
        }
        defer {
            rd_kafka_consumer_close(consumer)
            rd_kafka_destroy(consumer)
        }

        rd_kafka_poll_set_consumer(consumer)

        // Build topic partition list
        let topicPartitionList = rd_kafka_topic_partition_list_new(1)!
        defer { rd_kafka_topic_partition_list_destroy(topicPartitionList) }

        if let partition {
            rd_kafka_topic_partition_list_add(topicPartitionList, topic, partition)
        } else {
            // Get partition count from metadata and assign all
            var metadataPtr: UnsafePointer<rd_kafka_metadata_t>?
            let topicHandle = rd_kafka_topic_new(consumer, topic, nil)
            defer { if let topicHandle { rd_kafka_topic_destroy(topicHandle) } }

            let metaResult = rd_kafka_metadata(consumer, 0, topicHandle, &metadataPtr, Constants.kafkaTimeout)
            if metaResult == RD_KAFKA_RESP_ERR_NO_ERROR, let metadata = metadataPtr?.pointee {
                for i in 0 ..< Int(metadata.topic_cnt) {
                    let topicMeta = metadata.topics[i]
                    for j in 0 ..< Int(topicMeta.partition_cnt) {
                        rd_kafka_topic_partition_list_add(topicPartitionList, topic, topicMeta.partitions[j].id)
                    }
                }
                rd_kafka_metadata_destroy(metadataPtr)
            } else {
                // Fallback: add partition 0
                rd_kafka_topic_partition_list_add(topicPartitionList, topic, 0)
            }
        }

        // Set all partitions to start from beginning
        for i in 0 ..< Int(topicPartitionList.pointee.cnt) {
            topicPartitionList.pointee.elems[i].offset = Int64(RD_KAFKA_OFFSET_BEGINNING)
        }

        let assignResult = rd_kafka_assign(consumer, topicPartitionList)
        guard assignResult == RD_KAFKA_RESP_ERR_NO_ERROR else {
            let errStr = String(cString: rd_kafka_err2str(assignResult))
            throw SwifkaError.messageFetchFailed("Assign failed: \(errStr)")
        }

        // Poll messages
        var messages: [KafkaMessageRecord] = []
        var emptyPolls = 0
        let maxEmptyPolls = 3

        while messages.count < maxMessages, emptyPolls < maxEmptyPolls {
            guard let msg = rd_kafka_consumer_poll(consumer, Constants.defaultFetchTimeout) else {
                emptyPolls += 1
                continue
            }
            defer { rd_kafka_message_destroy(msg) }

            let message = msg.pointee

            // Skip errors
            if message.err != RD_KAFKA_RESP_ERR_NO_ERROR {
                if message.err == RD_KAFKA_RESP_ERR__PARTITION_EOF {
                    emptyPolls += 1
                }
                continue
            }

            emptyPolls = 0

            let key: Data? = if let keyPtr = message.key {
                Data(bytes: keyPtr, count: message.key_len)
            } else {
                nil
            }

            let value: Data? = if let payloadPtr = message.payload {
                Data(bytes: payloadPtr, count: message.len)
            } else {
                nil
            }

            let timestamp: Date? = {
                var tsType = RD_KAFKA_TIMESTAMP_NOT_AVAILABLE
                let ts = rd_kafka_message_timestamp(msg, &tsType)
                if ts >= 0, tsType != RD_KAFKA_TIMESTAMP_NOT_AVAILABLE {
                    return Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
                }
                return nil
            }()

            messages.append(KafkaMessageRecord(
                topic: topic,
                partition: message.partition,
                offset: message.offset,
                key: key,
                value: value,
                timestamp: timestamp,
            ))
        }

        return messages
    }

    // MARK: - Private Helpers

    private func setConfig(_ conf: OpaquePointer, key: String, value: String) throws {
        let errorChars = UnsafeMutablePointer<CChar>.allocate(capacity: stringSize)
        defer { errorChars.deallocate() }

        let result = rd_kafka_conf_set(conf, key, value, errorChars, stringSize)
        guard result == RD_KAFKA_CONF_OK else {
            let errorString = String(cString: errorChars)
            throw SwifkaError.connectionFailed("Config error [\(key)]: \(errorString)")
        }
    }

    deinit {
        if let handle {
            rd_kafka_destroy(handle)
        }
    }
}
