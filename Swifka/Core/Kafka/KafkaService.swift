import Crdkafka
import Foundation
import Kafka
import OSLog

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

    func connect(config: ClusterConfig, password: String? = nil) async throws {
        disconnect()

        let conf = rd_kafka_conf_new()!

        try setConfig(conf, key: "bootstrap.servers", value: config.bootstrapServers)
        try setConfig(conf, key: "client.id", value: "swifka-monitor")
        // Resilience: cap internal timeouts so librdkafka releases stale broker state faster
        try setConfig(conf, key: "socket.timeout.ms", value: "10000")
        try setConfig(conf, key: "reconnect.backoff.max.ms", value: "5000")

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

        // Use PRODUCER handle — we only need metadata, watermarks, and admin API calls.
        // CONSUMER handles run group coordination on rdk:main, which crashes (EXC_BAD_ACCESS)
        // when a broker goes down. browseMessages() creates its own separate consumer.
        guard let kafkaHandle = rd_kafka_new(RD_KAFKA_PRODUCER, conf, errorChars, stringSize) else {
            let errorString = String(cString: errorChars)
            throw SwifkaError.connectionFailed(errorString)
        }

        // Verify broker is reachable before accepting the connection
        let h = SendableHandle(pointer: kafkaHandle)
        let timeout = Constants.kafkaTimeout
        do {
            try await Self.offload {
                var metadataPtr: UnsafePointer<rd_kafka_metadata_t>?
                let result = rd_kafka_metadata(h.pointer, 0, nil, &metadataPtr, timeout)
                if let metadataPtr { rd_kafka_metadata_destroy(metadataPtr) }
                guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
                    let errStr = String(cString: rd_kafka_err2str(result))
                    throw SwifkaError.connectionFailed(errStr)
                }
            }
        } catch {
            Log.kafka.error("[KafkaService] connect: metadata verify failed — \(error.localizedDescription, privacy: .public)")
            rd_kafka_destroy(kafkaHandle)
            throw error
        }

        handle = kafkaHandle
        Log.kafka.info("[KafkaService] connect: handle created for \(config.bootstrapServers, privacy: .public)")
    }

    func disconnect() {
        guard let oldHandle = handle else { return }
        handle = nil
        Log.kafka.info("[KafkaService] disconnect: handle released")
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

        guard let testHandle = rd_kafka_new(RD_KAFKA_PRODUCER, testConf, errorChars, stringSize) else {
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

    /// Lightweight ping — measures round-trip latency to the broker in milliseconds.
    func ping() async throws -> Int {
        guard let handle else {
            throw SwifkaError.notConnected
        }
        let h = SendableHandle(pointer: handle)
        let timeout = Constants.kafkaTimeout

        return try await Self.offload {
            let start = DispatchTime.now()
            var metadataPtr: UnsafePointer<rd_kafka_metadata_t>?
            let result = rd_kafka_metadata(h.pointer, 0, nil, &metadataPtr, timeout)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            if let metadataPtr { rd_kafka_metadata_destroy(metadataPtr) }

            guard result == RD_KAFKA_RESP_ERR_NO_ERROR else {
                let errStr = String(cString: rd_kafka_err2str(result))
                throw SwifkaError.metadataFailed(errStr)
            }

            return Int(elapsed / 1_000_000) // nanoseconds → milliseconds
        }
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

            Log.kafka.debug("[KafkaService] fetchMetadata: \(brokers.count) brokers, \(topics.count) topics")
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
                    let assignments = Self.decodeMemberAssignment(
                        ptr: member.member_assignment,
                        size: Int(member.member_assignment_size),
                    )
                    members.append(GroupMemberInfo(
                        memberId: String(cString: member.member_id),
                        clientId: String(cString: member.client_id),
                        clientHost: String(cString: member.client_host),
                        assignments: assignments,
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

            Log.kafka.debug("[KafkaService] fetchConsumerGroups: \(groups.count) groups")
            return groups
        }
    }

    // MARK: - Member Assignment Decoder

    /// Decode the Kafka consumer protocol `member_assignment` binary blob.
    /// Format (big-endian): version(int16), numTopics(int32),
    /// then per topic: nameLen(int16), name(bytes), numPartitions(int32), partitions(int32 each).
    private static func decodeMemberAssignment(
        ptr: UnsafeMutableRawPointer?,
        size: Int,
    ) -> [PartitionAssignment] {
        guard let ptr, size > 4 else { return [] }
        let data = Data(bytes: ptr, count: size)
        var offset = 0

        func readInt16() -> Int16? {
            guard offset + 2 <= data.count else { return nil }
            let value = Int16(data[offset]) << 8 | Int16(data[offset + 1])
            offset += 2
            return value
        }

        func readInt32() -> Int32? {
            guard offset + 4 <= data.count else { return nil }
            let value = Int32(data[offset]) << 24 | Int32(data[offset + 1]) << 16
                | Int32(data[offset + 2]) << 8 | Int32(data[offset + 3])
            offset += 4
            return value
        }

        // Version
        guard readInt16() != nil else { return [] }

        // Number of topics
        guard let numTopics = readInt32(), numTopics >= 0 else { return [] }

        var assignments: [PartitionAssignment] = []
        for _ in 0 ..< numTopics {
            // Topic name (int16 length + bytes)
            guard let nameLen = readInt16(), nameLen >= 0, offset + Int(nameLen) <= data.count else { break }
            let topicName = String(data: data[offset ..< offset + Int(nameLen)], encoding: .utf8) ?? ""
            offset += Int(nameLen)

            // Partitions (int32 count + int32 each)
            guard let numPartitions = readInt32(), numPartitions >= 0 else { break }
            var partitions: [Int32] = []
            for _ in 0 ..< numPartitions {
                guard let partId = readInt32() else { break }
                partitions.append(partId)
            }
            partitions.sort()
            assignments.append(PartitionAssignment(topic: topicName, partitions: partitions))
        }
        return assignments
    }

    // MARK: - Consumer Group Offsets

    /// Fetch committed offsets for a consumer group using the admin API.
    /// Returns only partitions with valid committed offsets (offset >= 0).
    func fetchCommittedOffsets(
        group: String,
        partitions: [(topic: String, partition: Int32)],
    ) async throws -> [(topic: String, partition: Int32, offset: Int64)] {
        guard let handle else {
            throw SwifkaError.notConnected
        }
        let h = SendableHandle(pointer: handle)
        let timeout = Constants.kafkaTimeout
        // Copy partition data into a Sendable array of tuples
        let parts = partitions.map { (t: $0.topic, p: $0.partition) }

        return try await Self.offload {
            // 1. Build topic-partition list
            let tpl = rd_kafka_topic_partition_list_new(Int32(parts.count))!
            defer { rd_kafka_topic_partition_list_destroy(tpl) }
            for p in parts {
                rd_kafka_topic_partition_list_add(tpl, p.t, p.p)
            }

            // 2. Create admin request object
            var request: OpaquePointer? = rd_kafka_ListConsumerGroupOffsets_new(group, tpl)
            guard request != nil else {
                throw SwifkaError.consumerGroupsFailed("Failed to create ListConsumerGroupOffsets request")
            }
            defer { rd_kafka_ListConsumerGroupOffsets_destroy(request) }

            // 3. Create queue + options
            let queue = rd_kafka_queue_new(h.pointer)!
            defer { rd_kafka_queue_destroy(queue) }

            let options = rd_kafka_AdminOptions_new(h.pointer, RD_KAFKA_ADMIN_OP_LISTCONSUMERGROUPOFFSETS)!
            defer { rd_kafka_AdminOptions_destroy(options) }
            let errstr = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
            defer { errstr.deallocate() }
            rd_kafka_AdminOptions_set_request_timeout(options, Int32(timeout), errstr, 512)

            // 4. Submit request (API requires exactly 1 group per call)
            rd_kafka_ListConsumerGroupOffsets(h.pointer, &request, 1, options, queue)

            // 5. Poll for result
            guard let event = rd_kafka_queue_poll(queue, timeout) else {
                throw SwifkaError.consumerGroupsFailed("Timeout waiting for offset result")
            }
            defer { rd_kafka_event_destroy(event) }

            // 6. Extract result
            guard let result = rd_kafka_event_ListConsumerGroupOffsets_result(event) else {
                throw SwifkaError.consumerGroupsFailed("Unexpected event type")
            }

            var groupCnt = 0
            guard let groups = rd_kafka_ListConsumerGroupOffsets_result_groups(result, &groupCnt),
                  groupCnt > 0,
                  let groupResult = groups[0]
            else {
                throw SwifkaError.consumerGroupsFailed("No group results returned")
            }

            // Check group-level error
            if let err = rd_kafka_group_result_error(groupResult),
               rd_kafka_error_code(err) != RD_KAFKA_RESP_ERR_NO_ERROR
            {
                let msg = String(cString: rd_kafka_error_string(err))
                throw SwifkaError.consumerGroupsFailed(msg)
            }

            // 7. Parse committed offsets
            guard let resultPartitions = rd_kafka_group_result_partitions(groupResult) else {
                return []
            }

            var offsets: [(topic: String, partition: Int32, offset: Int64)] = []
            for i in 0 ..< Int(resultPartitions.pointee.cnt) {
                let tp = resultPartitions.pointee.elems[i]
                guard tp.offset >= 0 else { continue }
                offsets.append((
                    topic: String(cString: tp.topic),
                    partition: tp.partition,
                    offset: tp.offset,
                ))
            }
            return offsets
        }
    }

    // MARK: - Message Browsing

    func browseMessages(
        config: ClusterConfig,
        topic: String,
        partition: Int32?,
        maxMessages: Int = Constants.defaultMaxMessages,
        newestFirst: Bool = true,
        offsetFrom: Int64? = nil,
        offsetTo: Int64? = nil,
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

        // Normalize: swap if from > to
        let normFrom: Int64? = if let f = offsetFrom, let t = offsetTo, f > t { t } else { offsetFrom }
        let normTo: Int64? = if let f = offsetFrom, let t = offsetTo, f > t { f } else { offsetTo }

        // Set partition offsets based on direction and range, clamped to watermarks
        for i in 0 ..< Int(topicPartitionList.pointee.cnt) {
            let partId = topicPartitionList.pointee.elems[i].partition

            // Query watermarks for this partition to clamp offsets
            var low: Int64 = 0
            var high: Int64 = 0
            let wErr = rd_kafka_query_watermark_offsets(
                consumer, topic, partId, &low, &high, Constants.kafkaTimeout,
            )
            let hasWatermarks = wErr == RD_KAFKA_RESP_ERR_NO_ERROR

            if let from = normFrom, let _ = normTo {
                // Explicit range — clamp 'from' to valid range
                let clamped = hasWatermarks ? max(low, min(from, high)) : max(0, from)
                topicPartitionList.pointee.elems[i].offset = clamped
            } else if let from = normFrom {
                // Start from specific offset — clamp to valid range
                let clamped = hasWatermarks ? max(low, min(from, high)) : max(0, from)
                topicPartitionList.pointee.elems[i].offset = clamped
            } else if let to = normTo {
                // Fetch N messages ending at 'to'
                let clampedTo = hasWatermarks ? min(to, high) : to
                topicPartitionList.pointee.elems[i].offset = max(low, clampedTo - Int64(maxMessages) + 1)
            } else if newestFirst {
                // Newest: start near the end
                if hasWatermarks {
                    topicPartitionList.pointee.elems[i].offset = max(low, high - Int64(maxMessages))
                } else {
                    topicPartitionList.pointee.elems[i].offset = Int64(RD_KAFKA_OFFSET_END)
                }
            } else {
                // Oldest: start from beginning
                topicPartitionList.pointee.elems[i].offset = Int64(RD_KAFKA_OFFSET_BEGINNING)
            }
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
            // Allow early exit when the calling Task is cancelled
            if Task.isCancelled { break }

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

            // Skip messages past the upper bound
            if let to = normTo, message.offset > to {
                emptyPolls += 1
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

        Log.kafka.debug("[KafkaService] browseMessages: \(topic, privacy: .public) — \(messages.count) messages")
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
