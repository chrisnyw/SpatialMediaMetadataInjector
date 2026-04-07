//
//  MP4Container.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

/// Represents an MPEG-4 container box that holds child boxes.
class MP4Container: MP4Box {
    var padding: UInt64 = 0
    var children: [MP4Box] = []

    convenience init(padding: UInt64 = 0, headerSize: Int = 0) {
        self.init()
        self.padding = padding
        self.headerSize = headerSize
    }

    func resize() {
        contentSize = padding
        for child in children {
            if let container = child as? MP4Container {
                container.resize()
            }
            contentSize += child.size()
        }
    }

    override func printStructure(indent: String = "") {
        print("\(indent) \(name) [\(headerSize), \(contentSize)]")

        for (i, child) in children.enumerated() {
            var nextIndent = indent
                .replacingOccurrences(of: "├", with: "│")
                .replacingOccurrences(of: "└", with: " ")
                .replacingOccurrences(of: "─", with: " ")

            nextIndent += (i == children.count - 1) ? " └──" : " ├──"
            child.printStructure(indent: nextIndent)
        }
    }

    func remove(tag: String) {
        var newChildren: [MP4Box] = []
        contentSize = 0
        for child in children {
            if child.name != tag {
                newChildren.append(child)
                if let container = child as? MP4Container {
                    container.remove(tag: tag)
                }
                contentSize += child.size()
            }
        }
        children = newChildren
    }

    @discardableResult
    func add(_ element: MP4Box) -> Bool {
        for child in children {
            if child.name == element.name {
                if let childContainer = child as? MP4Container,
                   let elementContainer = element as? MP4Container {
                    return childContainer.merge(elementContainer)
                }
                print("Error, cannot merge leafs.")
                return false
            }
        }
        children.append(element)
        return true
    }

    func merge(_ element: MP4Container) -> Bool {
        assert(name == element.name)
        for subElement in element.children {
            if !add(subElement) { return false }
        }
        return true
    }

    override func save(inputFH: FileHandle, outputFH: FileHandle, delta: Int64) {
        writeBoxHeader(outputFH: outputFH)

        if padding > 0 {
            inputFH.seek(toFileOffset: contentStart())
            tagCopy(from: inputFH, to: outputFH, size: padding)
        }

        for child in children {
            child.save(inputFH: inputFH, outputFH: outputFH, delta: delta)
        }
    }

    func printBox(console: (String) -> Void) {
        for child in children {
            if let sa3d = child as? SA3DBox {
                sa3d.printBox(console: console)
            } else if let sv3d = child as? SV3DSubBox {
                sv3d.printBox(console: console)
            } else if let container = child as? MP4Container {
                container.printBox(console: console)
            }
        }
    }
}

// MARK: - Container / Element Loading

/// Smart loader: decides whether to load a leaf box or a container based on tag.
func loadElement(fh: FileHandle, position: UInt64, end: UInt64) -> MP4Box? {
    fh.seek(toFileOffset: position)

    var headerSize = 8
    guard let sizeU32 = fh.readUInt32BE() else { return nil }
    guard let name = fh.readTag() else { return nil }

    var totalSize = UInt64(sizeU32)
    let isLeaf = !MP4Constants.containersList.contains(name)
    let isSmallMP4A = (name == MP4Constants.tagMP4A && totalSize == 12)

    // Leaf box (or special cases)
    if isLeaf || isSmallMP4A {
        if name == MP4Constants.tagSA3D {
            return SA3DBox.load(fh: fh, position: position, end: end)
        }
        if SV3DBoxes.isSupportedBoxName(name) {
            return SV3DBoxes.load(fh: fh, position: position, end: end)
        }
        return loadBox(fh: fh, position: position, end: end)
    }

    // Container box
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
        print("Error: Container box size exceeds bounds.")
        return nil
    }

    // Determine padding based on box type
    var padding: UInt64 = 0

    if name == MP4Constants.tagSTSD {
        padding = 8
    }

    if MP4Constants.soundSampleDescriptions.contains(name) {
        let currentPos = fh.offsetInFile
        fh.seek(toFileOffset: currentPos + 8)
        guard let version = fh.readInt16BE() else { return nil }
        fh.seek(toFileOffset: currentPos)

        switch version {
        case 0:  padding = 28
        case 1:  padding = 28 + 16
        case 2:  padding = 64
        default: print("Unsupported sample description version: \(version)")
        }
    }

    if MP4Constants.videoSampleDescriptions.contains(name) {
        let currentPos = fh.offsetInFile
        fh.seek(toFileOffset: currentPos + 8)
        guard let version = fh.readInt16BE() else { return nil }
        fh.seek(toFileOffset: currentPos)

        padding = 78
        if version > 0 {
            print("Warning: video sample description version > 0: \(version)")
        }
    }

    let container = MP4Container()
    container.name = name
    container.position = position
    container.headerSize = headerSize
    container.contentSize = totalSize - UInt64(headerSize)
    container.padding = padding

    guard let children = loadMultiple(
        fh: fh,
        position: position + UInt64(headerSize) + padding,
        end: position + totalSize
    ) else {
        return nil
    }
    container.children = children

    return container
}

/// Loads all consecutive boxes in a range.
func loadMultiple(fh: FileHandle, position: UInt64, end: UInt64) -> [MP4Box]? {
    var loaded: [MP4Box] = []
    var pos = position

    while pos + 4 < end {
        guard let box = loadElement(fh: fh, position: pos, end: end) else {
            print("Error, failed to load box.")
            return nil
        }
        loaded.append(box)
        pos = box.position + box.size()
    }

    return loaded
}
