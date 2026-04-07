//
//  Constants.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation

enum MP4Constants {
    // Track types
    static let trakTypeVide = "vide"

    // Leaf types
    static let tagSTCO = "stco"
    static let tagCO64 = "co64"
    static let tagFREE = "free"
    static let tagMDAT = "mdat"
    static let tagXML  = "xml "
    static let tagHDLR = "hdlr"
    static let tagFTYP = "ftyp"
    static let tagESDS = "esds"
    static let tagSOUN = "soun"
    static let tagVIDE = "vide"
    static let tagSA3D = "SA3D"

    static let tagPRHD = "prhd"
    static let tagEQUI = "equi"
    static let tagSVHD = "svhd"
    static let tagST3D = "st3d"

    // Container types
    static let tagMOOV = "moov"
    static let tagUDTA = "udta"
    static let tagMETA = "meta"
    static let tagTRAK = "trak"
    static let tagMDIA = "mdia"
    static let tagMINF = "minf"
    static let tagSTBL = "stbl"
    static let tagSTSD = "stsd"
    static let tagUUID = "uuid"
    static let tagWAVE = "wave"

    static let tagSV3D = "sv3d"
    static let tagPROJ = "proj"

    // Sound sample descriptions
    static let tagNONE = "NONE"
    static let tagRAW  = "raw "
    static let tagTWOS = "twos"
    static let tagSOWT = "sowt"
    static let tagFL32 = "fl32"
    static let tagFL64 = "fl64"
    static let tagIN24 = "in24"
    static let tagIN32 = "in32"
    static let tagULAW = "ulaw"
    static let tagALAW = "alaw"
    static let tagLPCM = "lpcm"
    static let tagMP4A = "mp4a"
    static let tagOPUS = "Opus"

    // Video sample descriptions
    static let tagAVC1 = "avc1"
    static let tagVP09 = "vp09"
    static let tagAV01 = "av01"
    static let tagHEV1 = "hev1"
    static let tagHVC1 = "hvc1"
    static let tagDVH1 = "dvh1"
    static let tagAPCN = "apcn"
    static let tagAPCH = "apch"
    static let tagAPCS = "apcs"
    static let tagAPCO = "apco"
    static let tagAP4H = "ap4h"
    static let tagAP4X = "ap4x"

    static let soundSampleDescriptions: Set<String> = [
        tagNONE, tagRAW, tagTWOS, tagSOWT, tagFL32, tagFL64,
        tagIN24, tagIN32, tagULAW, tagALAW, tagLPCM, tagMP4A, tagOPUS,
    ]

    static let videoSampleDescriptions: Set<String> = [
        tagNONE, tagAVC1, tagVP09, tagAV01, tagHEV1, tagHVC1,
        tagDVH1, tagAPCN, tagAPCH, tagAPCS, tagAPCO, tagAP4H, tagAP4X,
    ]

    static let containersList: Set<String> = {
        var set: Set<String> = [
            tagMDIA, tagMINF, tagMOOV, tagSTBL, tagSTSD,
            tagTRAK, tagUDTA, tagWAVE, tagSV3D, tagPROJ,
        ]
        set.formUnion(soundSampleDescriptions)
        set.formUnion(videoSampleDescriptions)
        return set
    }()
}
