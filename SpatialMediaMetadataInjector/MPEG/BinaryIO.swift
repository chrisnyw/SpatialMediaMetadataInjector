//
//  BinaryIO.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

// MARK: - Errors

enum MP4Error: LocalizedError {
    case unexpectedEndOfFile
    case invalidBoxSize(size: UInt64, name: String, position: UInt64)
    case boxSizeExceedsBounds
    case invalidFile(reason: String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedEndOfFile:
            return "Unexpected end of file"
        case .invalidBoxSize(let size, let name, let position):
            return "Invalid size \(size) in \(name) at \(position)"
        case .boxSizeExceedsBounds:
            return "Box size exceeds bounds"
        case .invalidFile(let reason):
            return "Invalid file: \(reason)"
        case .unsupportedFormat(let msg):
            return msg
        }
    }
}

// MARK: - FileHandle Read Extensions

extension FileHandle {
    func readUInt8() -> UInt8? {
        let data = readData(ofLength: 1)
        guard data.count == 1 else { return nil }
        return data[0]
    }

    func readInt16BE() -> Int16? {
        let data = readData(ofLength: 2)
        guard data.count == 2 else { return nil }
        return Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
    }

    func readUInt16BE() -> UInt16? {
        let data = readData(ofLength: 2)
        guard data.count == 2 else { return nil }
        return UInt16(data[0]) << 8 | UInt16(data[1])
    }

    func readUInt32BE() -> UInt32? {
        let data = readData(ofLength: 4)
        guard data.count == 4 else { return nil }
        return UInt32(data[0]) << 24 | UInt32(data[1]) << 16
             | UInt32(data[2]) << 8  | UInt32(data[3])
    }

    func readInt32BE() -> Int32? {
        guard let u = readUInt32BE() else { return nil }
        return Int32(bitPattern: u)
    }

    func readUInt64BE() -> UInt64? {
        let data = readData(ofLength: 8)
        guard data.count == 8 else { return nil }
        var result: UInt64 = 0
        for byte in data { result = result << 8 | UInt64(byte) }
        return result
    }

    func readTag() -> String? {
        let data = readData(ofLength: 4)
        guard data.count == 4 else { return nil }
        return String(data: data, encoding: .ascii)
    }

    func readBytes(_ count: Int) -> Data? {
        let data = readData(ofLength: count)
        guard data.count == count else { return nil }
        return data
    }

    // MARK: Write Extensions

    func writeUInt8(_ value: UInt8) {
        write(Data([value]))
    }

    func writeUInt32BE(_ value: UInt32) {
        write(Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]))
    }

    func writeUInt64BE(_ value: UInt64) {
        var bytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { bytes[7 - i] = UInt8((value >> (i * 8)) & 0xFF) }
        write(Data(bytes))
    }

    func writeTag(_ tag: String) {
        if let data = tag.data(using: .ascii) { write(data) }
    }

    var fileSize: UInt64 {
        let current = offsetInFile
        let size = seekToEndOfFile()
        seek(toFileOffset: current)
        return size
    }
}

// MARK: - Bulk Copy

/// Copies a block of data between file handles in 64 MB chunks.
func tagCopy(from inputFH: FileHandle, to outputFH: FileHandle, size: UInt64) {
    let blockSize: UInt64 = 64 * 1024 * 1024
    var remaining = size
    while remaining > blockSize {
        outputFH.write(inputFH.readData(ofLength: Int(blockSize)))
        remaining -= blockSize
    }
    if remaining > 0 {
        outputFH.write(inputFH.readData(ofLength: Int(remaining)))
    }
}
