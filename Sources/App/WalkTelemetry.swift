import Foundation
import Darwin
import UIKit

final class WalkTelemetry {
    private var handle: FileHandle?
    private(set) var url: URL?
    private(set) var elapsed = 0.0, peak = 0.0, samples = 0, warnings = 0
    private var sampleTime = 0.0, seconds = 0.0, frames = 0, slowFrames = 0
    private(set) var fps = 0.0
    private var failed = false
    var logFailed: Bool { failed }
    static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576 : nil
    }
    func start() {
        stop(reason: "restarted")
        elapsed = 0; peak = 0; samples = 0; warnings = 0; seconds = 0; frames = 0; slowFrames = 0; sampleTime = -5; failed = false
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("walk-test-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try Data("# device=\(UIDevice.current.model),ios=\(UIDevice.current.systemVersion),duration=1800_active_seconds\ntime_s,footprint_mb,peak_mb,fps,slow_frames,texture_mb,nodes,textures,pending,loads,unloads,failures,budget_hits,memory_warnings,steps,x,y,thermal\n".utf8).write(to: file)
            handle = try FileHandle(forWritingTo: file); try handle?.seekToEnd(); url = file
        } catch { failed = true; url = nil }
    }
    func memoryWarning() { warnings += 1 }
    func tick(delta: Double) {
        // Background/lock-screen time is not counted as walking time.
        guard delta > 0 else { return }
        elapsed += delta; seconds += delta; frames += 1
        if delta > 0.05 { slowFrames += 1 }
        if seconds >= 1 { fps = Double(frames)/seconds; seconds = 0; frames = 0 }
    }
    func sample(stream: SceneStreamer, steps: Int, cell: Cell, force: Bool = false) -> Double? {
        let memory = Self.footprintMB()
        if let memory = memory { peak = max(peak, memory) }
        guard handle != nil, force || elapsed-sampleTime >= 5 else { return memory }
        sampleTime = elapsed; samples += 1
        let mb = memory.map { String(format: "%.2f", $0) } ?? "NA"
        write(String(format: "%.2f,%@,%.2f,%.1f,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
            elapsed, mb, peak, fps, slowFrames, Double(stream.bytes)/1048576, stream.nodeCount, stream.textureCount,
            stream.pendingCount, stream.loads, stream.unloads, stream.failures, stream.budgetHits, warnings, steps,
            cell.x, cell.y, ProcessInfo.processInfo.thermalState.rawValue))
        return memory
    }
    private func write(_ text: String) {
        do { try handle?.write(contentsOf: Data(text.utf8)) } catch { failed = true }
    }
    func stop(reason: String) {
        if handle != nil {
            write("# stopped=\(reason),active_seconds=\(elapsed),peak_mb=\(peak)\n")
            do { try handle?.close() } catch { failed = true }
            handle = nil
        }
    }
    deinit { try? handle?.close() }
}
