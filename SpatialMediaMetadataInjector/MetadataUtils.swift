//
//  MetadataUtils.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

// MARK: - Constants

let sphericalUUIDID = Data([
    0xFF, 0xCC, 0x82, 0x63, 0xF8, 0x55, 0x4A, 0x93,
    0x88, 0x14, 0x58, 0x7A, 0x02, 0x52, 0x1F, 0xDD,
])

private let rdfPrefix = " xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" "

private let sphericalXMLHeader = """
    <?xml version="1.0"?>\
    <rdf:SphericalVideo\n\
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"\n\
    xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/">
    """

private let sphericalXMLContents = """
    <GSpherical:Spherical>true</GSpherical:Spherical>\
    <GSpherical:Stitched>true</GSpherical:Stitched>\
    <GSpherical:StitchingSoftware>Spherical Metadata Tool</GSpherical:StitchingSoftware>\
    <GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType>
    """

private let notSphericalXMLContents = """
    <GSpherical:Spherical>false</GSpherical:Spherical>\
    <GSpherical:Stitched>false</GSpherical:Stitched>\
    <GSpherical:StitchingSoftware>Spherical Metadata Tool</GSpherical:StitchingSoftware>\
    <GSpherical:ProjectionType>rectangular</GSpherical:ProjectionType>
    """

private let sphericalXMLFooter = "</rdf:SphericalVideo>"

// MARK: - Data Types

struct SpatialAudioDescription {
    let order: Int
    let isSupported: Bool
    let hasHeadLockedStereo: Bool
}

class InjectionMetadata {
    var projection: String?
    var stereoMode: String?
    var bounds: [UInt32]?
    var video: String?          // V1 XML string
    var audio: [String: Any]?

    init(projection: String? = nil, stereoMode: String? = nil, boundsString: String? = nil) {
        self.projection = (projection == nil || projection == "none") ? nil : projection
        self.stereoMode = (stereoMode == nil || stereoMode == "none") ? nil : stereoMode

        if let bs = boundsString {
            let parts = bs.split(separator: ":").compactMap { UInt32($0, radix: 0) }
            if parts.count == 4 {
                self.bounds = parts.map { min($0, 0xFFFF_FFFF) }
            }
        }
    }
}

class ParsedMetadata {
    var video: [String: [String: String]] = [:]
    var audio: SA3DBox?
    var numAudioChannels: Int = 0
}

// MARK: - Spatial Audio Helpers

let maxSupportedAmbiXOrder = 1

func getSpatialAudioDescription(numChannels: Int) -> SpatialAudioDescription {
    for i in 1...maxSupportedAmbiXOrder {
        let ambi = (i + 1) * (i + 1)
        if ambi == numChannels {
            return SpatialAudioDescription(order: i, isSupported: true, hasHeadLockedStereo: false)
        }
        if ambi + 2 == numChannels {
            return SpatialAudioDescription(order: i, isSupported: true, hasHeadLockedStereo: true)
        }
    }
    return SpatialAudioDescription(order: -1, isSupported: false, hasHeadLockedStereo: false)
}

func getExpectedNumAudioChannels(type: String, order: Int, headLockedStereo: Bool) -> Int {
    let hls = headLockedStereo ? 2 : 0
    if type == "periphonic" { return (order + 1) * (order + 1) + hls }
    return -1
}

func getSpatialAudioMetadata(ambisonicOrder: Int, headLockedStereo: Bool) -> [String: Any] {
    let numCh = getExpectedNumAudioChannels(
        type: "periphonic", order: ambisonicOrder, headLockedStereo: headLockedStereo)
    return [
        "ambisonic_order": UInt32(ambisonicOrder),
        "head_locked_stereo": headLockedStereo,
        "ambisonic_type": "periphonic",
        "ambisonic_channel_ordering": "ACN",
        "ambisonic_normalization": "SN3D",
        "channel_map": Array(0..<numCh),
    ]
}

// MARK: - XML Generation

func generateSphericalXML(projection: String = "equirectangular",
                           stereo: String? = nil,
                           crop: String? = nil) -> String? {
    var extra = ""

    if stereo == "top-bottom" {
        extra += "<GSpherical:StereoMode>top-bottom</GSpherical:StereoMode>"
    } else if stereo == "left-right" {
        extra += "<GSpherical:StereoMode>left-right</GSpherical:StereoMode>"
    }

    if let crop = crop {
        let parts = crop.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 6 else {
            print("Error: Invalid crop params: \(crop)")
            return nil
        }
        let (w, h, fw, fh, x, y) = (parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
        guard fw > 0, fh > 0, w > 0, h > 0, w <= fw, h <= fh,
              x >= 0, y >= 0, x + w <= fw, y + h <= fh else {
            print("Error: Invalid crop dimensions")
            return nil
        }
        extra += "<GSpherical:CroppedAreaImageWidthPixels>\(w)</GSpherical:CroppedAreaImageWidthPixels>"
        extra += "<GSpherical:CroppedAreaImageHeightPixels>\(h)</GSpherical:CroppedAreaImageHeightPixels>"
        extra += "<GSpherical:FullPanoWidthPixels>\(fw)</GSpherical:FullPanoWidthPixels>"
        extra += "<GSpherical:FullPanoHeightPixels>\(fh)</GSpherical:FullPanoHeightPixels>"
        extra += "<GSpherical:CroppedAreaLeftPixels>\(x)</GSpherical:CroppedAreaLeftPixels>"
        extra += "<GSpherical:CroppedAreaTopPixels>\(y)</GSpherical:CroppedAreaTopPixels>"
    }

    let body = (projection == "equirectangular") ? sphericalXMLContents : notSphericalXMLContents
    return sphericalXMLHeader + body + extra + sphericalXMLFooter
}

// MARK: - UUID Box

private func sphericalUUID(xmlMetadata: String) -> MP4Box {
    let box = MP4Box()
    box.name = MP4Constants.tagUUID
    box.headerSize = 8

    var data = sphericalUUIDID
    if let xml = xmlMetadata.data(using: .utf8) { data.append(xml) }
    box.contents = data
    box.contentSize = UInt64(data.count)
    return box
}

// MARK: - V1 Injection (UUID / XML)

func mpeg4AddSphericalXMLV1(mp4: MP4File, inputFH: FileHandle, xml: String) -> Bool {
    guard let moov = mp4.moovBox else { return false }

    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }

        trak.remove(tag: MP4Constants.tagUUID)
        var isVideo = false

        for sub in trak.children {
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }
            for child in mdia.children {
                guard child.name == MP4Constants.tagHDLR else { continue }
                inputFH.seek(toFileOffset: child.contentStart() + 8)
                if inputFH.readTag() == MP4Constants.trakTypeVide {
                    isVideo = true
                    break
                }
            }
            if isVideo {
                if !trak.add(sphericalUUID(xmlMetadata: xml)) { return false }
                break
            }
        }
    }

    mp4.resize()
    return true
}

// MARK: - V2 Injection (SV3D / ST3D)

func mpeg4AddSphericalV2(mp4: MP4File, inputFH: FileHandle,
                          projection: String?, stereoMode: String?,
                          bounds: [UInt32]?) -> Bool {
    guard let moov = mp4.moovBox else { return false }

    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }
        for sub in trak.children {
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }
            for child in mdia.children {
                guard child.name == MP4Constants.tagHDLR else { continue }
                inputFH.seek(toFileOffset: child.contentStart() + 8)
                if inputFH.readTag() == MP4Constants.tagVIDE {
                    let ok = injectSpatialVideoV2(
                        inputFH: inputFH, videoMedia: mdia,
                        projection: projection, stereoMode: stereoMode, bounds: bounds)
                    mp4.resize()
                    return ok
                }
            }
        }
    }
    return false
}

private func injectSpatialVideoV2(inputFH: FileHandle, videoMedia: MP4Container,
                                   projection: String?, stereoMode: String?,
                                   bounds: [UInt32]?) -> Bool {
    for atom in videoMedia.children {
        guard atom.name == MP4Constants.tagMINF, let minf = atom as? MP4Container else { continue }
        for el in minf.children {
            guard el.name == MP4Constants.tagSTBL, let stbl = el as? MP4Container else { continue }
            for sub in stbl.children {
                guard sub.name == MP4Constants.tagSTSD, let stsd = sub as? MP4Container else { continue }
                for desc in stsd.children {
                    guard let sampleDesc = desc as? MP4Container,
                          MP4Constants.videoSampleDescriptions.contains(sampleDesc.name) else { continue }

                    if let sm = stereoMode {
                        let st3d = ST3DBox.create()
                        st3d.setStereoMode(from: sm)
                        sampleDesc.remove(tag: st3d.name)
                        sampleDesc.add(st3d)
                    }

                    if projection != nil {
                        let proj = MP4Container(padding: 0, headerSize: 8)
                        proj.name = MP4Constants.tagPROJ
                        proj.add(PRHDBox.create())
                        proj.add(EQUIBox.create(bounds: bounds))

                        let sv3d = MP4Container(padding: 0, headerSize: 8)
                        sv3d.name = MP4Constants.tagSV3D
                        sv3d.add(proj)

                        sampleDesc.remove(tag: sv3d.name)
                        sampleDesc.add(sv3d)
                    }
                }
            }
        }
    }
    return true
}

// MARK: - Spatial Audio Injection

func mpeg4AddSpatialAudio(mp4: MP4File, inputFH: FileHandle,
                           audioMetadata: [String: Any],
                           console: @escaping (String) -> Void) -> Bool {
    guard let moov = mp4.moovBox else { return false }

    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }
        for sub in trak.children {
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }
            for child in mdia.children {
                guard child.name == MP4Constants.tagHDLR else { continue }
                inputFH.seek(toFileOffset: child.contentStart() + 8)
                if inputFH.readTag() == MP4Constants.tagSOUN {
                    return injectSpatialAudioAtom(
                        inputFH: inputFH, audioMedia: mdia,
                        audioMetadata: audioMetadata, console: console)
                }
            }
        }
    }
    return true
}

private func injectSpatialAudioAtom(inputFH: FileHandle, audioMedia: MP4Container,
                                     audioMetadata: [String: Any],
                                     console: @escaping (String) -> Void) -> Bool {
    for atom in audioMedia.children {
        guard atom.name == MP4Constants.tagMINF, let minf = atom as? MP4Container else { continue }
        for el in minf.children {
            guard el.name == MP4Constants.tagSTBL, let stbl = el as? MP4Container else { continue }
            for sub in stbl.children {
                guard sub.name == MP4Constants.tagSTSD, let stsd = sub as? MP4Container else { continue }
                for desc in stsd.children {
                    guard let sampleDesc = desc as? MP4Container,
                          MP4Constants.soundSampleDescriptions.contains(sampleDesc.name) else { continue }

                    let numCh = getNumAudioChannels(stsd: stsd, inputFH: inputFH)
                    let type  = audioMetadata["ambisonic_type"] as? String ?? ""
                    let order = audioMetadata["ambisonic_order"] as? UInt32 ?? 0
                    let hls   = audioMetadata["head_locked_stereo"] as? Bool ?? false
                    let expected = getExpectedNumAudioChannels(
                        type: type, order: Int(order), headLockedStereo: hls)

                    if numCh != expected {
                        let hlsMsg = hls ? " with head-locked stereo" : ""
                        console("Error: Found \(numCh) channel(s), expected \(expected) for \(type) order \(order)\(hlsMsg).")
                        return false
                    }

                    let sa3d = SA3DBox.create(numChannels: UInt32(numCh), audioMetadata: audioMetadata)
                    sampleDesc.children.append(sa3d)
                }
            }
        }
    }
    return true
}

// MARK: - Audio Channel Counting

func getNumAudioChannels(stsd: MP4Container, inputFH: FileHandle) -> Int {
    guard stsd.name == MP4Constants.tagSTSD else { return -1 }
    for desc in stsd.children {
        if desc.name == MP4Constants.tagMP4A, let container = desc as? MP4Container {
            return getAACNumChannels(box: container, inputFH: inputFH)
        } else if MP4Constants.soundSampleDescriptions.contains(desc.name) {
            return getSampleDescriptionNumChannels(desc: desc, inputFH: inputFH)
        }
    }
    return -1
}

private func getSampleDescriptionNumChannels(desc: MP4Box, inputFH: FileHandle) -> Int {
    let saved = inputFH.offsetInFile
    defer { inputFH.seek(toFileOffset: saved) }

    inputFH.seek(toFileOffset: desc.contentStart() + 8)
    guard let version = inputFH.readInt16BE() else { return -1 }
    _ = inputFH.readData(ofLength: 2 + 4) // revision + vendor

    switch version {
    case 0:
        guard let ch = inputFH.readInt16BE() else { return -1 }
        return Int(ch)
    case 1:
        guard let ch = inputFH.readInt16BE() else { return -1 }
        return Int(ch)
    case 2:
        _ = inputFH.readData(ofLength: 2 + 2 + 2 + 2 + 4 + 4 + 8) // skip to num_channels
        guard let ch = inputFH.readInt32BE() else { return -1 }
        return Int(ch)
    default:
        print("Unsupported version for \(desc.name)")
        return -1
    }
}

private func getDescriptorLength(inputFH: FileHandle) -> Int {
    var length = 0
    for _ in 0..<4 {
        guard let byte = inputFH.readUInt8() else { return length }
        length = (length << 7) | Int(byte & 0x7F)
        if byte & 0x80 == 0 { break }
    }
    return length
}

private func getAACNumChannels(box: MP4Container, inputFH: FileHandle) -> Int {
    let saved = inputFH.offsetInFile
    defer { inputFH.seek(toFileOffset: saved) }

    guard box.name == MP4Constants.tagMP4A || box.name == MP4Constants.tagWAVE else { return -1 }

    for element in box.children {
        if element.name == MP4Constants.tagWAVE, let wave = element as? MP4Container {
            return getAACNumChannels(box: wave, inputFH: inputFH)
        }
        if element.name != MP4Constants.tagESDS { continue }

        inputFH.seek(toFileOffset: element.contentStart() + 4)

        // ES descriptor
        guard let esTag = inputFH.readUInt8(), esTag == 3 else { return -1 }
        _ = getDescriptorLength(inputFH: inputFH)
        _ = inputFH.readData(ofLength: 3)

        // Decoder config descriptor
        guard let cfgTag = inputFH.readUInt8(), cfgTag == 4 else { return -1 }
        _ = getDescriptorLength(inputFH: inputFH)
        _ = inputFH.readData(ofLength: 13)

        // Decoder specific descriptor
        guard let specTag = inputFH.readUInt8(), specTag == 5 else { return -1 }
        let specSize = getDescriptorLength(inputFH: inputFH)
        guard specSize >= 2, let descriptor = inputFH.readUInt16BE() else { return -1 }

        let samplingFreqIndex = (descriptor & 0x0780) >> 7
        if samplingFreqIndex == 0 {
            print("Error: >48kHz audio not supported")
            return -1
        }
        return Int((descriptor & 0x0078) >> 3)
    }
    return -1
}

func getNumAudioTracks(mp4: MP4File, inputFH: FileHandle) -> Int {
    guard let moov = mp4.moovBox else { return 0 }
    var count = 0
    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }
        for sub in trak.children {
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }
            for child in mdia.children {
                guard child.name == MP4Constants.tagHDLR else { continue }
                inputFH.seek(toFileOffset: child.contentStart() + 8)
                if inputFH.readTag() == MP4Constants.tagSOUN { count += 1 }
            }
        }
    }
    return count
}

// MARK: - Spherical XML Parsing

private let sphericalPrefix = "{http://ns.google.com/videos/1.0/spherical/}"
private let sphericalTagsList = [
    "Spherical", "Stitched", "StitchingSoftware", "ProjectionType",
    "SourceCount", "StereoMode", "InitialViewHeadingDegrees",
    "InitialViewPitchDegrees", "InitialViewRollDegrees", "Timestamp",
    "CroppedAreaImageWidthPixels", "CroppedAreaImageHeightPixels",
    "FullPanoWidthPixels", "FullPanoHeightPixels",
    "CroppedAreaLeftPixels", "CroppedAreaTopPixels",
]

private func parseSphericalXML(contents: String,
                                console: @escaping (String) -> Void) -> [String: String]? {
    guard let data = contents.data(using: .utf8) else { return nil }

    let delegate = SphericalXMLDelegate(console: console)
    let parser = XMLParser(data: data)
    parser.delegate = delegate

    if !parser.parse() {
        // Retry with RDF prefix
        var patched = contents
        if let range = patched.range(of: "<rdf:SphericalVideo") {
            patched.insert(contentsOf: rdfPrefix, at: range.upperBound)
        }
        guard let retryData = patched.data(using: .utf8) else { return nil }
        let retryDelegate = SphericalXMLDelegate(console: console)
        let retryParser = XMLParser(data: retryData)
        retryParser.delegate = retryDelegate
        if retryParser.parse() { return retryDelegate.result }
        return nil
    }
    return delegate.result
}

private class SphericalXMLDelegate: NSObject, XMLParserDelegate {
    var result: [String: String] = [:]
    private var currentText = ""
    private let console: (String) -> Void
    private let tagMap: [String: String]

    init(console: @escaping (String) -> Void) {
        self.console = console
        var map: [String: String] = [:]
        for tag in sphericalTagsList {
            map[sphericalPrefix + tag] = tag
            map["GSpherical:" + tag] = tag
        }
        self.tagMap = map
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        if let tag = tagMap[name] {
            console("\t\t\(tag) = \(currentText)")
            result[tag] = currentText
        }
    }
}

// MARK: - Parse from File

func parseSphericalMPEG4(mp4: MP4File, inputFH: FileHandle,
                          console: @escaping (String) -> Void) -> ParsedMetadata {
    let metadata = ParsedMetadata()
    guard let moov = mp4.moovBox else { return metadata }
    var trackNum = 0

    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }

        let trackName = "Track \(trackNum)"
        console("\t\(trackName)")
        trackNum += 1

        for sub in trak.children {
            // V1: UUID spherical metadata
            if sub.name == MP4Constants.tagUUID {
                let subID: Data
                if let c = sub.contents {
                    subID = c.prefix(16)
                } else {
                    inputFH.seek(toFileOffset: sub.contentStart())
                    subID = inputFH.readData(ofLength: 16)
                }

                if subID == sphericalUUIDID {
                    let xmlData: Data
                    if let c = sub.contents {
                        xmlData = Data(c.dropFirst(16))
                    } else {
                        xmlData = inputFH.readData(ofLength: Int(sub.contentSize) - 16)
                    }
                    if let xml = String(data: xmlData, encoding: .utf8) {
                        metadata.video[trackName] = parseSphericalXML(contents: xml, console: console) ?? [:]
                    }
                }
            }

            // MDIA: audio/video metadata
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }

            for mdiaChild in mdia.children {
                guard mdiaChild.name == MP4Constants.tagMINF,
                      let minf = mdiaChild as? MP4Container else { continue }
                for stblEl in minf.children {
                    guard stblEl.name == MP4Constants.tagSTBL,
                          let stbl = stblEl as? MP4Container else { continue }
                    for stsdEl in stbl.children {
                        guard stsdEl.name == MP4Constants.tagSTSD,
                              let stsd = stsdEl as? MP4Container else { continue }

                        // SA3D in sound sample descriptions
                        for containerEl in stsd.children {
                            guard let c = containerEl as? MP4Container,
                                  MP4Constants.soundSampleDescriptions.contains(c.name) else { continue }
                            metadata.numAudioChannels = getNumAudioChannels(stsd: stsd, inputFH: inputFH)
                            for child in c.children {
                                if let sa3d = child as? SA3DBox {
                                    sa3d.printBox(console: console)
                                    metadata.audio = sa3d
                                }
                            }
                        }

                        // SV3D / ST3D in video sample descriptions
                        for containerEl in stsd.children {
                            guard let c = containerEl as? MP4Container,
                                  MP4Constants.videoSampleDescriptions.contains(c.name) else { continue }
                            for child in c.children {
                                if child.name == MP4Constants.tagSV3D, let sv3d = child as? MP4Container {
                                    console("\t\tSV3D {")
                                    sv3d.printBox(console: console)
                                    console("\t\t}")
                                }
                                if let st3d = child as? ST3DBox {
                                    console("\t\tST3D {")
                                    st3d.printBox(console: console)
                                    console("\t\t}")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return metadata
}

// MARK: - High-Level API

func parseMetadata(inputURL: URL,
                   console: @escaping (String) -> Void) -> ParsedMetadata? {
    let ext = inputURL.pathExtension.lowercased()
    guard ["mp4", "mov"].contains(ext) else {
        console("Unknown file type")
        return nil
    }

    console("Processing: \(inputURL.path)")

    guard let inputFH = FileHandle(forReadingAtPath: inputURL.path) else {
        console("Error: cannot open file")
        return nil
    }
    defer { inputFH.closeFile() }

    guard let mp4 = MP4File.load(fh: inputFH) else {
        console("Error, file could not be opened.")
        return nil
    }

    console("Loaded file...")
    return parseSphericalMPEG4(mp4: mp4, inputFH: inputFH, console: console)
}

func removeMetadata(inputURL: URL, outputURL: URL,
                    console: @escaping (String) -> Void) -> Bool {
    guard let inputFH = FileHandle(forReadingAtPath: inputURL.path) else {
        console("Error: cannot open input file")
        return false
    }
    defer { inputFH.closeFile() }

    guard let mp4 = MP4File.load(fh: inputFH) else {
        console("Error: file could not be opened")
        return false
    }

    guard let moov = mp4.moovBox else {
        console("Error: no moov box found")
        return false
    }

    for element in moov.children {
        guard element.name == MP4Constants.tagTRAK,
              let trak = element as? MP4Container else { continue }

        // Remove V1 spherical UUID boxes
        trak.remove(tag: MP4Constants.tagUUID)

        for sub in trak.children {
            guard sub.name == MP4Constants.tagMDIA,
                  let mdia = sub as? MP4Container else { continue }
            for mdiaChild in mdia.children {
                guard mdiaChild.name == MP4Constants.tagMINF,
                      let minf = mdiaChild as? MP4Container else { continue }
                for stblEl in minf.children {
                    guard stblEl.name == MP4Constants.tagSTBL,
                          let stbl = stblEl as? MP4Container else { continue }
                    for stsdEl in stbl.children {
                        guard stsdEl.name == MP4Constants.tagSTSD,
                              let stsd = stsdEl as? MP4Container else { continue }
                        for desc in stsd.children {
                            guard let sampleDesc = desc as? MP4Container else { continue }
                            if MP4Constants.videoSampleDescriptions.contains(sampleDesc.name) {
                                sampleDesc.remove(tag: MP4Constants.tagSV3D)
                                sampleDesc.remove(tag: MP4Constants.tagST3D)
                            }
                            if MP4Constants.soundSampleDescriptions.contains(sampleDesc.name) {
                                sampleDesc.remove(tag: MP4Constants.tagSA3D)
                            }
                        }
                    }
                }
            }
        }
    }

    mp4.resize()

    console("Removed spatial metadata")
    _ = parseSphericalMPEG4(mp4: mp4, inputFH: inputFH, console: console)

    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    guard let outputFH = FileHandle(forWritingAtPath: outputURL.path) else {
        console("Error: cannot create output file")
        return false
    }
    defer { outputFH.closeFile() }

    mp4.saveFile(inputFH: inputFH, outputFH: outputFH)
    return true
}

func injectMetadata(inputURL: URL, outputURL: URL,
                    metadata: InjectionMetadata,
                    console: @escaping (String) -> Void) -> Bool {
    guard let inputFH = FileHandle(forReadingAtPath: inputURL.path) else {
        console("Error: cannot open input file")
        return false
    }
    defer { inputFH.closeFile() }

    guard let mp4 = MP4File.load(fh: inputFH) else {
        console("Error: file could not be opened")
        return false
    }

    // V1 XML
    if let xml = metadata.video {
        if !mpeg4AddSphericalXMLV1(mp4: mp4, inputFH: inputFH, xml: xml) {
            console("Error: failed to insert spherical data")
            return false
        }
    }

    // V2
    if metadata.projection != nil || metadata.stereoMode != nil {
        if !mpeg4AddSphericalV2(mp4: mp4, inputFH: inputFH,
                                 projection: metadata.projection,
                                 stereoMode: metadata.stereoMode,
                                 bounds: metadata.bounds) {
            console("Error: failed to insert spherical data v2")
            return false
        }
    }

    // Spatial audio
    if let audio = metadata.audio {
        let tracks = getNumAudioTracks(mp4: mp4, inputFH: inputFH)
        if tracks > 1 {
            console("Error: Expected 1 audio track, found \(tracks)")
            return false
        }
        if !mpeg4AddSpatialAudio(mp4: mp4, inputFH: inputFH,
                                  audioMetadata: audio, console: console) {
            console("Error: failed to insert spatial audio data")
            return false
        }
    }

    console("Saved file settings")
    _ = parseSphericalMPEG4(mp4: mp4, inputFH: inputFH, console: console)

    // Write output file
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    guard let outputFH = FileHandle(forWritingAtPath: outputURL.path) else {
        console("Error: cannot create output file")
        return false
    }
    defer { outputFH.closeFile() }

    mp4.saveFile(inputFH: inputFH, outputFH: outputFH)
    return true
}
