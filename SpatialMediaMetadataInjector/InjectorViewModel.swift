//
//  InjectorViewModel.swift
//  SpatialMediaMetadataInjector
//
//  Created by Chris Ng on 2026-04-07.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class InjectorViewModel {

    // MARK: - State

    private(set) var inputURL: URL?
    private(set) var parsedMetadata: ParsedMetadata?
    var isSpherical = true
    var isStereo3D = false
    var isSpatialAudio = false
    private(set) var statusMessage = "Click Open to load your 360 video."
    private(set) var isError = false
    private(set) var isProcessing = false
    private(set) var spatialAudioDesc: SpatialAudioDescription?
    private(set) var logMessages: [String] = []

    // MARK: - Derived

    var logText: String {
        logMessages.joined(separator: "\n")
    }

    var hasMetadata: Bool {
        guard let meta = parsedMetadata else { return false }
        let hasVideo = meta.video.values.contains { !$0.isEmpty }
        return hasVideo || meta.audio != nil
    }

    var canInject: Bool {
        isSpherical && inputURL != nil && !isProcessing
    }

    var canRemove: Bool {
        inputURL != nil && !isProcessing && hasMetadata
    }

    // MARK: - Actions

    func sphericalChanged() {
        if !isSpherical {
            isStereo3D = false
            isSpatialAudio = false
        }
    }

    // MARK: - File Import

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()

            inputURL = url
            logMessages = []
            isError = false
            statusMessage = "Loading: \(url.lastPathComponent)..."

            var logs: [String] = []
            let console: (String) -> Void = { msg in logs.append(msg) }

            if let parsed = parseMetadata(inputURL: url, console: console) {
                parsedMetadata = parsed
                spatialAudioDesc = getSpatialAudioDescription(numChannels: parsed.numAudioChannels)

                statusMessage = "Loaded: \(url.lastPathComponent)"
                isSpherical = true

                if let firstMeta = parsed.video.values.first {
                    isSpherical = firstMeta["Spherical"] == "true"
                    isStereo3D = firstMeta["StereoMode"] == "top-bottom"
                } else {
                    isStereo3D = false
                }

                isSpatialAudio = parsed.audio != nil
            } else {
                isError = true
                statusMessage = "Failed to load: \(url.lastPathComponent)"
                inputURL = nil
            }

            logMessages = logs
            if accessing { url.stopAccessingSecurityScopedResource() }

        case .failure(let error):
            isError = true
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Injection

    func beginInjection() {
        guard let inputURL else { return }
        guard let outputURL = promptSavePanel(inputURL: inputURL, suffix: "_injected") else { return }
        performInjection(inputURL: inputURL, outputURL: outputURL)
    }

    private func performInjection(inputURL: URL, outputURL: URL) {
        let stereo3D = isStereo3D
        let spatialAudio = isSpatialAudio
        let audioDesc = spatialAudioDesc

        isProcessing = true
        logMessages = []
        statusMessage = "Processing..."

        let accessing = inputURL.startAccessingSecurityScopedResource()

        Task {
            let (success, logs) = await Task.detached(priority: .userInitiated) {
                () -> (Bool, [String]) in
                var logs: [String] = []
                let console: (String) -> Void = { msg in logs.append(msg) }

                let metadata = InjectionMetadata()

                let stereo = stereo3D ? "top-bottom" : nil
                metadata.video = generateSphericalXML(stereo: stereo)
                metadata.projection = "equirectangular"
                metadata.stereoMode = stereo3D ? "top-bottom" : nil

                if spatialAudio, let desc = audioDesc, desc.isSupported {
                    metadata.audio = getSpatialAudioMetadata(
                        ambisonicOrder: desc.order,
                        headLockedStereo: desc.hasHeadLockedStereo)
                }

                let success = injectMetadata(
                    inputURL: inputURL, outputURL: outputURL,
                    metadata: metadata, console: console)

                if accessing { inputURL.stopAccessingSecurityScopedResource() }
                return (success, logs)
            }.value

            handleProcessingResult(success: success, logs: logs, outputURL: outputURL, failureMessage: "Failed to inject metadata")
        }
    }

    // MARK: - Removal

    func beginRemoval() {
        guard let inputURL else { return }
        guard let outputURL = promptSavePanel(inputURL: inputURL, suffix: "_removed") else { return }
        performRemoval(inputURL: inputURL, outputURL: outputURL)
    }

    private func performRemoval(inputURL: URL, outputURL: URL) {
        isProcessing = true
        logMessages = []
        statusMessage = "Removing metadata..."

        let accessing = inputURL.startAccessingSecurityScopedResource()

        Task {
            let (success, logs) = await Task.detached(priority: .userInitiated) {
                () -> (Bool, [String]) in
                var logs: [String] = []
                let console: (String) -> Void = { msg in logs.append(msg) }

                let success = removeMetadata(
                    inputURL: inputURL, outputURL: outputURL, console: console)

                if accessing { inputURL.stopAccessingSecurityScopedResource() }
                return (success, logs)
            }.value

            handleProcessingResult(success: success, logs: logs, outputURL: outputURL, failureMessage: "Failed to remove metadata")
        }
    }

    // MARK: - Helpers

    private func promptSavePanel(inputURL: URL, suffix: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            inputURL.pathExtension.lowercased() == "mov" ? .quickTimeMovie : .mpeg4Movie
        ]
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension
        panel.nameFieldStringValue = "\(baseName)\(suffix).\(ext)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func handleProcessingResult(success: Bool, logs: [String], outputURL: URL, failureMessage: String) {
        isProcessing = false
        logMessages = logs

        if success {
            statusMessage = "Saved: \(outputURL.lastPathComponent)"
            isError = false

            var parseLogs: [String] = []
            let parseConsole: (String) -> Void = { msg in parseLogs.append(msg) }
            if let refreshed = parseMetadata(inputURL: outputURL, console: parseConsole) {
                parsedMetadata = refreshed
                spatialAudioDesc = getSpatialAudioDescription(numChannels: refreshed.numAudioChannels)
                inputURL = outputURL
            }
        } else {
            statusMessage = failureMessage
            isError = true
        }
    }
}
