//
//  LearnRecorder.swift
//  aslan-browser
//

import Foundation

@MainActor
class LearnRecorder {

    enum State { case idle, recording }

    private(set) var state: State = .idle
    private(set) var name: String?
    private(set) var actions: [[String: Any]] = []
    private(set) var startTimestamp: Date?
    private var nextSeq: Int = 1
    private var screenshotDir: String?

    // MARK: - Start

    func start(name: String) throws -> String {
        guard state == .idle else {
            throw BrowserError.learnModeError("Already recording")
        }

        self.state = .recording
        self.name = name
        self.startTimestamp = Date()
        self.actions = []
        self.nextSeq = 1

        let dir = "/tmp/aslan-learn/\(name)"
        let fm = FileManager.default

        if fm.fileExists(atPath: dir) {
            try? fm.removeItem(atPath: dir)
        }
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        self.screenshotDir = dir
        return dir
    }

    // MARK: - Stop

    func stop() throws -> [String: Any] {
        guard state == .recording else {
            throw BrowserError.learnModeError("Not recording")
        }

        let duration = Date().timeIntervalSince(startTimestamp!) * 1000

        let result: [String: Any] = [
            "name": name as Any,
            "startedAt": startTimestamp!.timeIntervalSince1970 * 1000,
            "duration": duration,
            "actionCount": actions.count,
            "screenshotDir": screenshotDir as Any,
            "actions": actions
        ]

        self.state = .idle
        self.name = nil
        self.startTimestamp = nil
        self.screenshotDir = nil

        return result
    }

    // MARK: - Add Action

    @discardableResult
    func addAction(_ action: [String: Any], screenshotData: String?, tabId: String) -> Int {
        guard state == .recording else { return 0 }

        let seq = nextSeq
        var entry: [String: Any] = action
        entry["seq"] = seq
        entry["timestamp"] = Date().timeIntervalSince1970 * 1000
        entry["tabId"] = tabId

        if let base64 = screenshotData, let dir = screenshotDir {
            let path = "\(dir)/step-\(String(format: "%03d", seq)).jpg"
            entry["screenshot"] = path
            writeScreenshot(base64: base64, to: path)
        }

        actions.append(entry)
        nextSeq += 1
        return seq
    }

    // MARK: - Add Annotation

    @discardableResult
    func addAnnotation(text: String) -> Int {
        guard state == .recording else { return 0 }

        let seq = nextSeq
        let entry: [String: Any] = [
            "seq": seq,
            "type": "annotation",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "text": text
        ]

        actions.append(entry)
        nextSeq += 1
        return seq
    }

    // MARK: - Status

    func status() -> [String: Any] {
        return [
            "recording": state == .recording,
            "name": name as Any,
            "actionCount": actions.count
        ]
    }

    // MARK: - Private

    private func writeScreenshot(base64: String, to path: String) {
        Task.detached {
            guard let data = Data(base64Encoded: base64) else { return }
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
