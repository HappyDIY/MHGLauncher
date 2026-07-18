#!/usr/bin/env swift

import Darwin
import Foundation

struct Options {
    let pid: Int32
    let duration: Double
    let intervalMilliseconds: UInt32
    let normalizedLimit: Double

    init?(arguments: [String]) {
        guard
            arguments.count >= 2,
            let pid = Int32(arguments[1]),
            pid > 0
        else {
            return nil
        }

        let duration = arguments.count > 2 ? Double(arguments[2]) ?? 10 : 10
        let intervalMilliseconds = arguments.count > 3
            ? UInt32(arguments[3]) ?? 100
            : 100
        let normalizedLimit = arguments.count > 4
            ? Double(arguments[4]) ?? 20
            : 20
        guard
            duration > 0,
            intervalMilliseconds > 0,
            normalizedLimit >= 0
        else {
            return nil
        }

        self.pid = pid
        self.duration = duration
        self.intervalMilliseconds = intervalMilliseconds
        self.normalizedLimit = normalizedLimit
    }
}

func taskCPUTicks(pid: Int32) -> UInt64? {
    var info = proc_taskinfo()
    let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
    let actualSize = proc_pidinfo(
        pid,
        PROC_PIDTASKINFO,
        0,
        &info,
        expectedSize
    )
    guard actualSize == expectedSize else {
        return nil
    }
    return info.pti_total_user + info.pti_total_system
}

guard let options = Options(arguments: CommandLine.arguments) else {
    fputs(
        "用法: sample-frontend-cpu.swift PID [秒数] [采样间隔毫秒] [整机占比上限]\n",
        stderr
    )
    exit(2)
}

var timebase = mach_timebase_info_data_t()
_ = mach_timebase_info(&timebase)
guard var previousCPU = taskCPUTicks(pid: options.pid) else {
    fputs("无法读取目标进程 CPU 数据\n", stderr)
    exit(2)
}

let processorCount = max(ProcessInfo.processInfo.processorCount, 1)
let sampleCount = max(
    Int(options.duration * 1_000 / Double(options.intervalMilliseconds)),
    1
)
var previousWall = DispatchTime.now().uptimeNanoseconds
var processPeak = 0.0

for _ in 0..<sampleCount {
    usleep(options.intervalMilliseconds * 1_000)
    guard let currentCPU = taskCPUTicks(pid: options.pid) else {
        fputs("采样期间目标进程已退出\n", stderr)
        exit(2)
    }

    let currentWall = DispatchTime.now().uptimeNanoseconds
    let cpuNanoseconds = Double(currentCPU - previousCPU)
        * Double(timebase.numer) / Double(timebase.denom)
    let wallNanoseconds = Double(currentWall - previousWall)
    processPeak = max(processPeak, cpuNanoseconds / wallNanoseconds * 100)
    previousCPU = currentCPU
    previousWall = currentWall
}

let normalizedPeak = processPeak / Double(processorCount)
print(String(
    format: "process_peak=%.2f%% machine_share_peak=%.2f%% logical_cores=%d",
    processPeak,
    normalizedPeak,
    processorCount
))
exit(normalizedPeak <= options.normalizedLimit ? 0 : 1)
