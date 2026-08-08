// Dấu macOS — bundle watcher for ad-hoc signature changes (0.1.7).
// Watches /Applications/Dau.app/Contents/MacOS/Dau for writes/replaces (brew upgrade, manual cp).
// When the on-disk binary changes while the old process is still running, the old
// CFMachPort holds the previous ad-hoc hash and TCC grade is stale → typing fails.
// The watcher triggers a safe relaunch (sleep 0.5; open) after the file stabilizes.

import Foundation

final class BundleWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private let path: String
    private let onChange: () -> Void

    init(path: String? = nil, onChange: @escaping () -> Void) {
        let defaultPath = Bundle.main.executablePath ?? "/Applications/Dau.app/Contents/MacOS/Dau"
        self.path = path ?? defaultPath
        self.onChange = onChange
    }

    func start() {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fd = fd
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    private func schedule() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = work
        // Debounce 0.9s — brew's copy/unzip may fire multiple events.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    deinit { stop() }
}
