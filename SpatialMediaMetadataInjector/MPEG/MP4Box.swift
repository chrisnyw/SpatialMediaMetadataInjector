//
//  MP4Box.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

/// Represents an MPEG-4 leaf box (atom).
class MP4Box {
    var name: String = ""
    var position: UInt64 = 0
    var headerSize: Int = 0
    var contentSize: UInt64 = 0
    var contents: Data?

    func contentStart() -> UInt64 {
        position + UInt64(headerSize)
    }

    func size() -> UInt64 {
        UInt64(headerSize) + contentSize
    }

    func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)

        if contentStart() > 0 {
            inputFH.seek(toFileOffset: contentStart())
        }

        if name == MP4Constants.tagSTCO {
            indexCopy(inputFH: inputFH, outputFH: outputFH, mode32: true, delta: delta)
        } else if name == MP4Constants.tagCO64 {
            indexCopy(inputFH: inputFH, outputFH: outputFH, mode32: false, delta: delta)
        } else if let data = contents {
            outputFH.write(data)
        } else {
            tagCopy(from: inputFH, to: outputFH, size: contentSize)
        }
    }

    func writeBoxHeader(outputFH: FileHandle) {
        if headerSize == 16 {
            outputFH.writeUInt32BE(1)
            outputFH.writeTag(name)
            outputFH.writeUInt64BE(size())
        } else {
            outputFH.writeUInt32BE(UInt32(size()))
            outputFH.writeTag(name)
        }
    }

    func printStructure(indent: String = "") {
        print("\(indent) \(name) [\(headerSize), \(contentSize)]")
    }

    // MARK: - Index Table Copy (stco / co64)

    /// Updates chunk-offset index tables when the moov/mdat layout changes.
    private func indexCopy(inputFH: FileHandle, outputFH: FileHandle,
                           mode32: Bool, delta: Int64) {
        if let data = contents {
            indexCopyFromData(data, outputFH: outputFH, mode32: mode32, delta: delta)
        } else {
            inputFH.seek(toFileOffset: contentStart())
            indexCopyFromHandle(inputFH, outputFH: outputFH, mode32: mode32, delta: delta)
        }
    }

    private func indexCopyFromHandle(_ fh: FileHandle, outputFH: FileHandle,
                                     mode32: Bool, delta: Int64) {
        guard let header = fh.readUInt32BE(),
              let count  = fh.readUInt32BE() else { return }

        outputFH.writeUInt32BE(header)
        outputFH.writeUInt32BE(count)

        for _ in 0..<count {
            if mode32 {
                guard let value = fh.readUInt32BE() else { return }
                outputFH.writeUInt32BE(UInt32(Int64(value) + delta))
            } else {
                guard let value = fh.readUInt64BE() else { return }
                outputFH.writeUInt64BE(UInt64(Int64(value) + delta))
            }
        }
    }

    private func indexCopyFromData(_ data: Data, outputFH: FileHandle,
                                   mode32: Bool, delta: Int64) {
        var offset = 0

        func readU32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let v = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16
                  | UInt32(data[offset+2]) << 8  | UInt32(data[offset+3])
            offset += 4
            return v
        }
        func readU64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            var r: UInt64 = 0
            for i in 0..<8 { r = r << 8 | UInt64(data[offset + i]) }
            offset += 8
            return r
        }

        guard let header = readU32(), let count = readU32() else { return }
        outputFH.writeUInt32BE(header)
        outputFH.writeUInt32BE(count)

        for _ in 0..<count {
            if mode32 {
                guard let v = readU32() else { return }
                outputFH.writeUInt32BE(UInt32(Int64(v) + delta))
            } else {
                guard let v = readU64() else { return }
                outputFH.writeUInt64BE(UInt64(Int64(v) + delta))
            }
        }
    }
}

// MARK: - Box Loading

/// Loads a leaf box at the given position.
func loadBox(fh: FileHandle, position: UInt64, end: UInt64) -> MP4Box? {
    fh.seek(toFileOffset: position)

    var headerSize = 8
    guard let sizeU32 = fh.readUInt32BE() else { return nil }
    guard let name = fh.readTag() else { return nil }

    var totalSize = UInt64(sizeU32)
    if sizeU32 == 1 {
        guard let extended = fh.readUInt64BE() else { return nil }
        totalSize = extended
        headerSize = 16
    }

    if totalSize < 8 {
        print("Error, invalid size \(totalSize) in \(name) at \(position)")
        return nil
    }
    if (position + totalSize) > end {
        print("Error: Leaf box size exceeds bounds.")
        return nil
    }

    let box = MP4Box()
    box.name = name
    box.position = position
    box.headerSize = headerSize
    box.contentSize = totalSize - UInt64(headerSize)
    return box
}
