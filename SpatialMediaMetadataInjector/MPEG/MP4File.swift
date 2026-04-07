//
//  MP4File.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

/// Represents the root structure of an MPEG-4 file.
class MP4File: MP4Container {
    var moovBox: MP4Container?
    var freeBox: MP4Box?
    var firstMdatBox: MP4Box?
    var ftypBox: MP4Box?
    var firstMdatPosition: UInt64 = 0

    /// Loads an MP4/MOV file from a URL.
    static func load(from url: URL) -> MP4File? {
        guard let fh = FileHandle(forReadingAtPath: url.path) else {
            print("Error: cannot open file at \(url.path)")
            return nil
        }
        defer { fh.closeFile() }
        return load(fh: fh)
    }

    /// Loads an MP4/MOV file from an open file handle.
    static func load(fh: FileHandle) -> MP4File? {
        let size = fh.fileSize

        guard let contents = loadMultiple(fh: fh, position: 0, end: size),
              !contents.isEmpty else {
            print("Error, failed to load .mp4 file.")
            return nil
        }

        let mp4 = MP4File()
        mp4.children = contents

        for element in mp4.children {
            if element.name == MP4Constants.tagMOOV {
                mp4.moovBox = element as? MP4Container
            }
            if element.name == MP4Constants.tagFREE {
                mp4.freeBox = element
            }
            if element.name == MP4Constants.tagMDAT && mp4.firstMdatBox == nil {
                mp4.firstMdatBox = element
            }
            if element.name == MP4Constants.tagFTYP {
                mp4.ftypBox = element
            }
        }

        guard mp4.moovBox != nil else {
            print("Error, file does not contain moov box.")
            return nil
        }
        guard let firstMdat = mp4.firstMdatBox else {
            print("Error, file does not contain mdat box.")
            return nil
        }

        mp4.firstMdatPosition = firstMdat.position + UInt64(firstMdat.headerSize)

        mp4.contentSize = 0
        for element in mp4.children {
            mp4.contentSize += element.size()
        }

        return mp4
    }

    /// Saves the (possibly modified) file structure to an output file handle.
    func saveFile(inputFH: FileHandle, outputFH: FileHandle) {
        resize()

        // Compute the new mdat content position
        var newMdatContentPos: UInt64 = 0
        for element in children {
            if element.name == MP4Constants.tagMDAT {
                newMdatContentPos += UInt64(element.headerSize)
                break
            }
            newMdatContentPos += element.size()
        }

        let delta = Int64(newMdatContentPos) - Int64(firstMdatPosition)

        for element in children {
            element.save(inputFH: inputFH, outputFH: outputFH, delta: delta)
        }
    }

    override func printStructure(indent: String = "") {
        print("mpeg4 [\(contentSize)]")
        for (i, element) in children.enumerated() {
            let nextIndent = (i == children.count - 1) ? " └──" : " ├──"
            element.printStructure(indent: nextIndent)
        }
    }
}
