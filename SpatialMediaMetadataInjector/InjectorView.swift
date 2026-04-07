//
//  InjectorView.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import SwiftUI
import UniformTypeIdentifiers

struct InjectorView: View {
    @State private var viewModel = InjectorViewModel()
    @State private var showFileImporter = false
    @State private var showLog = false

    var body: some View {
        @Bindable var vm = viewModel

        HStack(alignment: .top, spacing: 0) {
            ControlsPanel(
                viewModel: viewModel,
                showFileImporter: $showFileImporter,
                showLog: $showLog
            )
            .padding(20)
            .frame(minWidth: 400)

            if viewModel.inputURL != nil {
                Divider()

                MetadataInfoPanel(
                    parsedMetadata: viewModel.parsedMetadata,
                    spatialAudioDesc: viewModel.spatialAudioDesc
                )
                .padding(20)
                .frame(minWidth: 260, maxWidth: 320)
            }
        }
        .frame(minWidth: viewModel.inputURL != nil ? 720 : 480)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleFileImport(result)
        }
    }
}

// MARK: - Controls Panel

private struct ControlsPanel: View {
    @Bindable var viewModel: InjectorViewModel
    @Binding var showFileImporter: Bool
    @Binding var showLog: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.statusMessage)
                .foregroundStyle(viewModel.isError ? .red : Color.accentColor)
                .font(.callout)
                .lineLimit(2)
                .padding(.bottom, 4)

            Divider()

            Toggle("My video is spherical (360)", isOn: $viewModel.isSpherical)
                .disabled(viewModel.inputURL == nil)
                .onChange(of: viewModel.isSpherical) {
                    viewModel.sphericalChanged()
                }

            Toggle("My video is stereoscopic 3D (top/bottom layout)", isOn: $viewModel.isStereo3D)
                .disabled(!viewModel.isSpherical || viewModel.inputURL == nil)

            Toggle(isOn: $viewModel.isSpatialAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My video has spatial audio (ambiX ACN/SN3D)")
                    if viewModel.spatialAudioDesc?.hasHeadLockedStereo == true {
                        Text("with head-locked stereo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!viewModel.isSpherical || viewModel.inputURL == nil || !(viewModel.spatialAudioDesc?.isSupported ?? false))

            Divider()

            HStack(spacing: 20) {
                Button("Open") {
                    showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Inject Metadata") {
                    viewModel.beginInjection()
                }
                .disabled(!viewModel.canInject)
                .buttonStyle(.borderedProminent)

                Button("Remove Metadata") {
                    viewModel.beginRemoval()
                }
                .disabled(!viewModel.canRemove)
                .buttonStyle(.bordered)

                if viewModel.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !viewModel.logMessages.isEmpty {
                DisclosureGroup("Processing Log", isExpanded: $showLog) {
                    ScrollView {
                        Text(viewModel.logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Metadata Info Panel

struct MetadataInfoPanel: View {
    let parsedMetadata: ParsedMetadata?
    let spatialAudioDesc: SpatialAudioDescription?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current File Metadata")
                .font(.headline)

            Divider()

            if let meta = parsedMetadata {
                MetadataSection(title: "Spherical Video") {
                    if let firstVideo = meta.video.values.first, !firstVideo.isEmpty {
                        let spherical = firstVideo["Spherical"] == "true"
                        MetadataRow(label: "Spherical", value: spherical ? "Yes" : "No", isPresent: spherical)
                        MetadataRow(label: "Projection", value: firstVideo["ProjectionType"] ?? "—")
                        MetadataRow(label: "Stereo Mode", value: firstVideo["StereoMode"] ?? "none")
                        MetadataRow(label: "Stitched", value: firstVideo["Stitched"] ?? "—")

                        if let sw = firstVideo["StitchingSoftware"] {
                            MetadataRow(label: "Software", value: sw)
                        }
                        if let cw = firstVideo["CroppedAreaImageWidthPixels"],
                           let ch = firstVideo["CroppedAreaImageHeightPixels"] {
                            MetadataRow(label: "Crop Size", value: "\(cw) x \(ch)")
                        }
                        if let fw = firstVideo["FullPanoWidthPixels"],
                           let fh = firstVideo["FullPanoHeightPixels"] {
                            MetadataRow(label: "Full Pano", value: "\(fw) x \(fh)")
                        }
                    } else {
                        Label("No spherical metadata found", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                MetadataSection(title: "Spatial Audio") {
                    if let audio = meta.audio {
                        MetadataRow(label: "Status", value: "Present", isPresent: true)
                        MetadataRow(label: "Type", value: audio.ambisonicTypeName())
                        MetadataRow(label: "Order", value: "\(audio.ambisonicOrder)")
                        MetadataRow(label: "Ordering", value: audio.ambisonicChannelOrderingName())
                        MetadataRow(label: "Normalization", value: audio.ambisonicNormalizationName())
                        MetadataRow(label: "Channels", value: "\(audio.numChannels)")
                        MetadataRow(label: "Head-Locked", value: audio.headLockedStereo ? "Yes" : "No")
                    } else {
                        if spatialAudioDesc?.isSupported == true {
                            Label("No spatial audio metadata (supported: \(meta.numAudioChannels) ch)", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Label("No spatial audio (\(meta.numAudioChannels) ch — not ambisonics)", systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Open a video file to inspect its metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Metadata Section

private struct MetadataSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
        }
    }
}

// MARK: - Metadata Row

private struct MetadataRow: View {
    let label: String
    let value: String
    var isPresent: Bool? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let present = isPresent {
                Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(present ? .green : .secondary)
                    .font(.caption)
                    .accessibilityLabel(present ? "Present" : "Not present")
            }
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    InjectorView()
}
