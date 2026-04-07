//
//  SA3DBox.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

/// Represents an SA3D box containing spatial audio metadata.
class SA3DBox: MP4Box {
    static let ambisonicTypes: [String: UInt8] = ["periphonic": 0]
    static let ambisonicOrderings: [String: UInt8] = ["ACN": 0]
    static let ambisonicNormalizations: [String: UInt8] = ["SN3D": 0]

    var version: UInt8 = 0
    var ambisonicType: UInt8 = 0
    var headLockedStereo: Bool = false
    var ambisonicOrder: UInt32 = 0
    var ambisonicChannelOrdering: UInt8 = 0
    var ambisonicNormalization: UInt8 = 0
    var numChannels: UInt32 = 0
    var channelMap: [UInt32] = []

    override init() {
        super.init()
        name = MP4Constants.tagSA3D
        headerSize = 8
    }

    // MARK: - Loading

    static func load(fh: FileHandle, position: UInt64, end: UInt64) -> SA3DBox? {
        fh.seek(toFileOffset: position)

        let box = SA3DBox()
        box.position = position

        guard let size = fh.readUInt32BE(),
              let tag  = fh.readTag() else { return nil }

        guard tag == MP4Constants.tagSA3D else {
            print("Error: box is not an SA3D box.")
            return nil
        }
        if position + UInt64(size) > end {
            print("Error: SA3D box size exceeds bounds.")
            return nil
        }

        box.contentSize = UInt64(size) - UInt64(box.headerSize)

        guard let version          = fh.readUInt8(),
              let ambiTypeByte     = fh.readUInt8(),
              let ambiOrder        = fh.readUInt32BE(),
              let channelOrdering  = fh.readUInt8(),
              let normalization    = fh.readUInt8(),
              let numCh            = fh.readUInt32BE()
        else { return nil }

        box.version = version
        box.headLockedStereo = (ambiTypeByte & 0x80) != 0
        box.ambisonicType = ambiTypeByte & 0x7F
        box.ambisonicOrder = ambiOrder
        box.ambisonicChannelOrdering = channelOrdering
        box.ambisonicNormalization = normalization
        box.numChannels = numCh

        for _ in 0..<numCh {
            guard let ch = fh.readUInt32BE() else { return nil }
            box.channelMap.append(ch)
        }

        return box
    }

    // MARK: - Creation

    static func create(numChannels: UInt32, audioMetadata: [String: Any]) -> SA3DBox {
        let box = SA3DBox()
        box.version = 0
        box.contentSize = 0

        // version (1 byte)
        box.contentSize += 1

        // ambisonic type + head-locked flag (1 byte)
        if let typeStr = audioMetadata["ambisonic_type"] as? String,
           let val = ambisonicTypes[typeStr] {
            box.ambisonicType = val
        }
        box.headLockedStereo = audioMetadata["head_locked_stereo"] as? Bool ?? false
        box.contentSize += 1

        // ambisonic order (4 bytes)
        box.ambisonicOrder = audioMetadata["ambisonic_order"] as? UInt32 ?? 0
        box.contentSize += 4

        // channel ordering (1 byte)
        if let str = audioMetadata["ambisonic_channel_ordering"] as? String,
           let val = ambisonicOrderings[str] {
            box.ambisonicChannelOrdering = val
        }
        box.contentSize += 1

        // normalization (1 byte)
        if let str = audioMetadata["ambisonic_normalization"] as? String,
           let val = ambisonicNormalizations[str] {
            box.ambisonicNormalization = val
        }
        box.contentSize += 1

        // num channels (4 bytes)
        box.numChannels = numChannels
        box.contentSize += 4

        // channel map (4 bytes each)
        if let map = audioMetadata["channel_map"] as? [Int] {
            for ch in map {
                box.channelMap.append(UInt32(ch))
                box.contentSize += 4
            }
        }

        return box
    }

    // MARK: - Metadata Strings

    func ambisonicTypeName() -> String {
        SA3DBox.ambisonicTypes.first { $0.value == ambisonicType }?.key ?? "unknown"
    }

    func ambisonicChannelOrderingName() -> String {
        SA3DBox.ambisonicOrderings.first { $0.value == ambisonicChannelOrdering }?.key ?? "unknown"
    }

    func ambisonicNormalizationName() -> String {
        SA3DBox.ambisonicNormalizations.first { $0.value == ambisonicNormalization }?.key ?? "unknown"
    }

    func printBox(console: (String) -> Void) {
        console("\t\tAmbisonic Type: \(ambisonicTypeName())")
        console("\t\tHead-Locked Stereo: \(headLockedStereo)")
        console("\t\tAmbisonic Order: \(ambisonicOrder)")
        console("\t\tChannel Ordering: \(ambisonicChannelOrderingName())")
        console("\t\tNormalization: \(ambisonicNormalizationName())")
        console("\t\tChannels: \(numChannels)")
        console("\t\tChannel Map: \(channelMap)")
    }

    func getMetadataString() -> String {
        "\(ambisonicNormalizationName()), \(ambisonicChannelOrderingName()), " +
        "\(ambisonicTypeName()), Order \(ambisonicOrder), " +
        "\(numChannels) Channel(s), Map: \(channelMap)"
    }

    // MARK: - Saving

    override func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)

        let typeByte: UInt8 = headLockedStereo
            ? (ambisonicType | 0x80)
            : (ambisonicType & 0x7F)

        outputFH.writeUInt8(version)
        outputFH.writeUInt8(typeByte)
        outputFH.writeUInt32BE(ambisonicOrder)
        outputFH.writeUInt8(ambisonicChannelOrdering)
        outputFH.writeUInt8(ambisonicNormalization)
        outputFH.writeUInt32BE(numChannels)

        for ch in channelMap {
            outputFH.writeUInt32BE(ch)
        }
    }
}
