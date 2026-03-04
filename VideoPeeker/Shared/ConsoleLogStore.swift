//
//  ConsoleLogStore.swift
//  VideoPeeker
//
//  Captures stdout/stderr so logs are viewable in-app.
//

import Foundation
import Combine
import SwiftUI

final class ConsoleLogStore: ObservableObject {
    static let shared = ConsoleLogStore()

    @Published private(set) var lines: [String] = []

    private var isStarted = false
    private var pipe: Pipe?
    private var stdoutDupFd: Int32?
    private var stderrDupFd: Int32?
    private var pendingFragment = ""

    private let maxLines = 2500

    private init() {}

    @MainActor
    func startCaptureIfNeeded() {
        if isStarted { return }
        isStarted = true

        let pipe = Pipe()
        self.pipe = pipe

        // Duplicate original stdout/stderr so we can still mirror logs to Xcode console.
        let outDup = dup(STDOUT_FILENO)
        let errDup = dup(STDERR_FILENO)
        stdoutDupFd = outDup
        stderrDupFd = errDup

        // Redirect stdout/stderr to the pipe.
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }

            // Mirror to original fds (best-effort) so Xcode console still shows output.
            self?.mirrorToOriginalStreams(data: data)

            guard let text = String(data: data, encoding: .utf8), text.isEmpty == false else { return }
            Task { @MainActor [weak self] in
                self?.appendText(text)
            }
        }
    }

    @MainActor
    func clear() {
        lines.removeAll()
        pendingFragment = ""
    }

    private func mirrorToOriginalStreams(data: Data) {
        if let outDup = stdoutDupFd, outDup >= 0 {
            let outHandle = FileHandle(fileDescriptor: outDup, closeOnDealloc: false)
            try? outHandle.write(contentsOf: data)
        }

        if let errDup = stderrDupFd, errDup >= 0 {
            let errHandle = FileHandle(fileDescriptor: errDup, closeOnDealloc: false)
            try? errHandle.write(contentsOf: data)
        }
    }

    @MainActor
    private func appendText(_ text: String) {
        // Normalize line endings and split. Keep trailing fragment to avoid chopped lines.
        let normalized = (pendingFragment + text).replacingOccurrences(of: "\r\n", with: "\n")
        var parts = normalized.components(separatedBy: "\n")

        if normalized.hasSuffix("\n") == false {
            pendingFragment = parts.popLast() ?? ""
        } else {
            pendingFragment = ""
            if parts.last == "" {
                _ = parts.popLast()
            }
        }

        for part in parts where part.isEmpty == false {
            lines.append(part)
        }

        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

