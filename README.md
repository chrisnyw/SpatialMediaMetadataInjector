# Spatial Media Metadata Injector

A native macOS app for inspecting, injecting, and removing spatial metadata from 360/VR video files.

Built for creators working with spherical video, stereoscopic 3D, and spatial audio who need a simple tool to tag their media with the correct metadata for playback on platforms like YouTube, Meta Quest, and Apple Vision Pro.

## Features

- **Inspect** existing spatial metadata in MP4/MOV files
- **Inject** spherical video metadata (Google Spherical Video V1 + ISO V2)
- **Inject** stereoscopic 3D mode (top-bottom layout)
- **Inject** spatial audio metadata (AmbiX ACN/SN3D, first-order ambisonics)
- **Remove** all spatial metadata from a file
- Non-destructive: always writes to a new output file

## Supported Metadata

| Type | Format | Details |
|------|--------|---------|
| Spherical Video V1 | UUID/XML (Google) | Equirectangular projection, stitching info |
| Spherical Video V2 | SV3D/ST3D/PROJ (ISO) | Equirectangular projection with optional bounds |
| Stereo 3D | ST3D box | Top-bottom or left-right layout |
| Spatial Audio | SA3D box | AmbiX first-order ambisonics (4 ch), optional head-locked stereo (+2 ch) |

## Requirements

- macOS 14.0 (Sonoma) or later
- No external dependencies

## Supported File Formats

- `.mp4` (MPEG-4)
- `.mov` (QuickTime)

## Usage

1. **Open** a video file via the Open button or `Cmd+O`
2. The right panel displays any existing spatial metadata found in the file
3. Configure the options:
   - **Spherical (360)** - mark the video as spherical with equirectangular projection
   - **Stereoscopic 3D** - set top-bottom stereo mode (requires spherical)
   - **Spatial Audio** - tag audio tracks as ambisonics (auto-detected from channel count)
4. Click **Inject Metadata** to write a new file with the selected metadata
5. Click **Remove Metadata** to strip all spatial metadata and save a clean copy

## Building

Open `SpatialMediaMetadataInjector.xcodeproj` in Xcode 15 or later and build the `SpatialMediaMetadataInjector` target.

No package manager setup is required. The project uses only Apple system frameworks (SwiftUI, AppKit, Foundation).

## Project Structure

```
SpatialMediaMetadataInjector/
  SpatialMediaApp.swift        # App entry point
  InjectorView.swift           # Main UI (SwiftUI)
  InjectorViewModel.swift      # Business logic
  MetadataUtils.swift          # Metadata parsing, injection, and removal
  MPEG/
    BinaryIO.swift             # FileHandle binary read/write extensions
    Constants.swift            # MP4 box type tags and constants
    MP4Box.swift               # Base MPEG-4 box (atom)
    MP4Container.swift         # Container box with child hierarchy
    MP4File.swift              # Top-level MP4/MOV file parser
    SA3DBox.swift              # Spatial Audio 3D box
    SV3DBoxes.swift            # Spherical Video V2 boxes (SV3D, ST3D, PROJ, PRHD, EQUI)
```

## License

This project is provided as-is for personal and educational use.
