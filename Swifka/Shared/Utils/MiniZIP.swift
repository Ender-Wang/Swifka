import Foundation

// MARK: - Minimal ZIP Archive Builder & Reader

/// Produces and reads uncompressed (stored) ZIP archives from in-memory file entries.
/// Zero external dependencies — used for XLSX export and full data backup.
nonisolated enum MiniZIP {
    /// Creates an uncompressed ZIP archive from the given file entries.
    static func archive(_ files: [(path: String, data: Data)]) -> Data {
        var body = Data()
        var directory = Data()
        let count = files.count

        for (path, content) in files {
            let pathBytes = Data(path.utf8)
            let crc = CRC32.compute(content)
            let size = UInt32(content.count)
            let offset = UInt32(body.count)

            // Local file header
            body.append(zipUInt32: 0x0403_4B50)
            body.append(zipUInt16: 20) // version needed to extract
            body.append(zipUInt16: 0) // general purpose bit flag
            body.append(zipUInt16: 0) // compression method: stored
            body.append(zipUInt16: 0) // last mod file time
            body.append(zipUInt16: 0) // last mod file date
            body.append(zipUInt32: crc)
            body.append(zipUInt32: size) // compressed size
            body.append(zipUInt32: size) // uncompressed size
            body.append(zipUInt16: UInt16(pathBytes.count))
            body.append(zipUInt16: 0) // extra field length
            body.append(pathBytes)
            body.append(content)

            // Central directory entry
            directory.append(zipUInt32: 0x0201_4B50)
            directory.append(zipUInt16: 20) // version made by
            directory.append(zipUInt16: 20) // version needed
            directory.append(zipUInt16: 0) // flags
            directory.append(zipUInt16: 0) // compression
            directory.append(zipUInt16: 0) // last mod time
            directory.append(zipUInt16: 0) // last mod date
            directory.append(zipUInt32: crc)
            directory.append(zipUInt32: size)
            directory.append(zipUInt32: size)
            directory.append(zipUInt16: UInt16(pathBytes.count))
            directory.append(zipUInt16: 0) // extra field length
            directory.append(zipUInt16: 0) // file comment length
            directory.append(zipUInt16: 0) // disk number start
            directory.append(zipUInt16: 0) // internal file attributes
            directory.append(zipUInt32: 0) // external file attributes
            directory.append(zipUInt32: offset) // relative offset of local header
            directory.append(pathBytes)
        }

        let cdOffset = UInt32(body.count)
        body.append(directory)

        // End of central directory record
        body.append(zipUInt32: 0x0605_4B50)
        body.append(zipUInt16: 0) // number of this disk
        body.append(zipUInt16: 0) // disk where CD starts
        body.append(zipUInt16: UInt16(count)) // CD records on this disk
        body.append(zipUInt16: UInt16(count)) // total CD records
        body.append(zipUInt32: UInt32(directory.count)) // size of central directory
        body.append(zipUInt32: cdOffset) // offset of CD start
        body.append(zipUInt16: 0) // ZIP comment length

        return body
    }

    /// Extracts files from an uncompressed (stored) ZIP archive.
    static func extract(_ data: Data) throws -> [(path: String, data: Data)] {
        // Find end-of-central-directory record (scan backwards)
        let eocdSig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard data.count >= 22 else { throw ZIPError.invalidArchive }

        var eocdOffset = -1
        for i in stride(from: data.count - 22, through: 0, by: -1) {
            if data[data.startIndex + i] == eocdSig[0],
               data[data.startIndex + i + 1] == eocdSig[1],
               data[data.startIndex + i + 2] == eocdSig[2],
               data[data.startIndex + i + 3] == eocdSig[3]
            {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0 else { throw ZIPError.invalidArchive }

        let entryCount = Int(data.readUInt16(at: eocdOffset + 10))
        let cdOffset = Int(data.readUInt32(at: eocdOffset + 16))

        // Parse central directory
        var files: [(path: String, data: Data)] = []
        var pos = cdOffset

        for _ in 0 ..< entryCount {
            guard pos + 46 <= data.count else { throw ZIPError.invalidArchive }

            let sig = data.readUInt32(at: pos)
            guard sig == 0x0201_4B50 else { throw ZIPError.invalidArchive }

            let compression = data.readUInt16(at: pos + 10)
            guard compression == 0 else { throw ZIPError.unsupportedCompression }

            let uncompressedSize = Int(data.readUInt32(at: pos + 24))
            let nameLen = Int(data.readUInt16(at: pos + 28))
            let extraLen = Int(data.readUInt16(at: pos + 30))
            let commentLen = Int(data.readUInt16(at: pos + 32))
            let localHeaderOffset = Int(data.readUInt32(at: pos + 42))

            let nameStart = data.startIndex + pos + 46
            guard nameStart + nameLen <= data.endIndex else { throw ZIPError.invalidArchive }
            let nameData = data[nameStart ..< nameStart + nameLen]
            guard let name = String(data: nameData, encoding: .utf8) else { throw ZIPError.invalidArchive }

            // Skip directory entries
            if !name.hasSuffix("/") {
                // Read from local file header
                guard localHeaderOffset + 30 <= data.count else { throw ZIPError.invalidArchive }
                let localNameLen = Int(data.readUInt16(at: localHeaderOffset + 26))
                let localExtraLen = Int(data.readUInt16(at: localHeaderOffset + 28))
                let fileDataStart = data.startIndex + localHeaderOffset + 30 + localNameLen + localExtraLen
                guard fileDataStart + uncompressedSize <= data.endIndex else { throw ZIPError.invalidArchive }

                let fileData = Data(data[fileDataStart ..< fileDataStart + uncompressedSize])
                files.append((path: name, data: fileData))
            }

            pos += 46 + nameLen + extraLen + commentLen
        }

        return files
    }

    enum ZIPError: Error, LocalizedError {
        case invalidArchive
        case unsupportedCompression

        var errorDescription: String? {
            switch self {
            case .invalidArchive: "Invalid or corrupted ZIP archive"
            case .unsupportedCompression: "Compressed ZIP entries are not supported"
            }
        }
    }
}

// MARK: - CRC-32

nonisolated enum CRC32 {
    static let table: [UInt32] = (0 ..< 256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0 ..< 8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Data Extensions for ZIP I/O

nonisolated extension Data {
    mutating func append(zipUInt16 value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func append(zipUInt32 value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        let start = startIndex + offset
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0, from: start ..< start + 2) }
        return UInt16(littleEndian: value)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0, from: start ..< start + 4) }
        return UInt32(littleEndian: value)
    }
}
