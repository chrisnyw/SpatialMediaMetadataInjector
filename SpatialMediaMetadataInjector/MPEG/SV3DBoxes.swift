//
//  SV3DBoxes.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

// MARK: - Dispatcher

enum SV3DBoxes {
    static func isSupportedBoxName(_ name: String) -> Bool {
        name == MP4Constants.tagPRHD ||
        name == MP4Constants.tagEQUI ||
        name == MP4Constants.tagST3D
    }

    static func load(fh: FileHandle, position: UInt64, end: UInt64) -> MP4Box? {
        fh.seek(toFileOffset: position)
        guard let _ = fh.readUInt32BE(),
              let name = fh.readTag() else { return nil }

        let box: SV3DSubBox
        switch name {
        case MP4Constants.tagPRHD: box = PRHDBox()
        case MP4Constants.tagEQUI: box = EQUIBox()
        case MP4Constants.tagST3D: box = ST3DBox()
        default:
            print("Error: \(name) is not a supported SV3D sub-box.")
            return nil
        }

        // Re-read from position for consistent size parsing
        fh.seek(toFileOffset: position)
        guard let size = fh.readUInt32BE() else { return nil }
        _ = fh.readTag() // skip name (already read)

        box.position = position
        box.contentSize = UInt64(size) - UInt64(box.headerSize)
        box.loadContent(fh: fh)
        return box
    }
}

// MARK: - Base Class

class SV3DSubBox: MP4Box {
    func loadContent(fh: FileHandle) {}
    func printBox(console: (String) -> Void) {}
    func getMetadataString() -> String { "" }
}

// MARK: - PRHD (Projection Header)

class PRHDBox: SV3DSubBox {
    var poseYawDegrees: UInt32 = 0
    var posePitchDegrees: UInt32 = 0
    var poseRollDegrees: UInt32 = 0

    override init() {
        super.init()
        name = MP4Constants.tagPRHD
        headerSize = 8
        contentSize = 16
    }

    static func create() -> PRHDBox { PRHDBox() }

    override func printBox(console: (String) -> Void) {
        console("\t\t\tPRHD {")
        console("\t\t\t\tPose Yaw: \(poseYawDegrees)")
        console("\t\t\t\tPose Pitch: \(posePitchDegrees)")
        console("\t\t\t\tPose Roll: \(poseRollDegrees)")
        console("\t\t\t}")
    }

    override func getMetadataString() -> String {
        "yaw:\(poseYawDegrees), pitch:\(posePitchDegrees), roll:\(poseRollDegrees)"
    }

    override func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)
        outputFH.writeUInt32BE(0) // version + flags
        outputFH.writeUInt32BE(poseYawDegrees)
        outputFH.writeUInt32BE(posePitchDegrees)
        outputFH.writeUInt32BE(poseRollDegrees)
    }

    override func loadContent(fh: FileHandle) {
        _ = fh.readUInt32BE() // version + flags
        poseYawDegrees   = fh.readUInt32BE() ?? 0
        posePitchDegrees = fh.readUInt32BE() ?? 0
        poseRollDegrees  = fh.readUInt32BE() ?? 0
    }
}

// MARK: - EQUI (Equirectangular Projection)

class EQUIBox: SV3DSubBox {
    var boundsTop: UInt32 = 0
    var boundsBottom: UInt32 = 0
    var boundsLeft: UInt32 = 0
    var boundsRight: UInt32 = 0

    override init() {
        super.init()
        name = MP4Constants.tagEQUI
        headerSize = 8
        contentSize = 20
    }

    convenience init(bounds: [UInt32]?) {
        self.init()
        if let b = bounds, b.count == 4 {
            boundsTop    = b[0]
            boundsBottom = b[1]
            boundsLeft   = b[2]
            boundsRight  = b[3]
        }
    }

    static func create(bounds: [UInt32]? = nil) -> EQUIBox { EQUIBox(bounds: bounds) }

    override func printBox(console: (String) -> Void) {
        console("\t\t\tEQUI {")
        console("\t\t\t\tTop: \(boundsTop)")
        console("\t\t\t\tBottom: \(boundsBottom)")
        console("\t\t\t\tLeft: \(boundsLeft)")
        console("\t\t\t\tRight: \(boundsRight)")
        console("\t\t\t}")
    }

    override func getMetadataString() -> String {
        "Equi (top:\(boundsTop), bottom:\(boundsBottom), left:\(boundsLeft), right:\(boundsRight))"
    }

    override func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)
        outputFH.writeUInt32BE(0) // version + flags
        outputFH.writeUInt32BE(boundsTop)
        outputFH.writeUInt32BE(boundsBottom)
        outputFH.writeUInt32BE(boundsLeft)
        outputFH.writeUInt32BE(boundsRight)
    }

    override func loadContent(fh: FileHandle) {
        _ = fh.readUInt32BE() // version + flags
        boundsTop    = fh.readUInt32BE() ?? 0
        boundsBottom = fh.readUInt32BE() ?? 0
        boundsLeft   = fh.readUInt32BE() ?? 0
        boundsRight  = fh.readUInt32BE() ?? 0
    }
}

// MARK: - ST3D (Stereo Mode)

class ST3DBox: SV3DSubBox {
    var stereoMode: UInt8 = 0

    override init() {
        super.init()
        name = MP4Constants.tagST3D
        headerSize = 8
        contentSize = 5
    }

    static func create() -> ST3DBox { ST3DBox() }

    func setStereoMode(from string: String) {
        switch string {
        case "mono":        stereoMode = 0
        case "top-bottom":  stereoMode = 1
        case "left-right":  stereoMode = 2
        default:            print("Error: unknown stereo mode \(string)")
        }
    }

    override func printBox(console: (String) -> Void) {
        console("\t\t\tStereo Mode: \(stereoMode)")
    }

    override func getMetadataString() -> String {
        "Stereo Mode: \(stereoMode)"
    }

    override func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)
        outputFH.writeUInt32BE(0) // version + flags
        outputFH.writeUInt8(stereoMode)
    }

    override func loadContent(fh: FileHandle) {
        _ = fh.readUInt32BE() // version + flags
        stereoMode = fh.readUInt8() ?? 0
    }
}
