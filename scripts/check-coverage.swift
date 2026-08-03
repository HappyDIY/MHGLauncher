#!/usr/bin/env swift
import Foundation

struct Metric: Decodable { let percent: Double }
struct Totals: Decodable { let lines: Metric; let regions: Metric; let functions: Metric }
struct CoverageData: Decodable { let totals: Totals }
struct Coverage: Decodable { let data: [CoverageData] }
struct Baseline: Decodable { let lines: Double; let regions: Double; let functions: Double }

guard CommandLine.arguments.count == 3 else {
    fputs("用法：check-coverage.swift <coverage.json> <baseline.json>\n", stderr)
    exit(2)
}
let decoder = JSONDecoder()
let coverage = try decoder.decode(Coverage.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let baseline = try decoder.decode(Baseline.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
guard let totals = coverage.data.first?.totals else { throw NSError(domain: "Coverage", code: 1) }
let values = [("lines", totals.lines.percent, baseline.lines),
              ("regions", totals.regions.percent, baseline.regions),
              ("functions", totals.functions.percent, baseline.functions)]
var failed = false
for (name, actual, expected) in values {
    print("\(name): \(String(format: "%.2f", actual))%（基线 \(String(format: "%.2f", expected))%）")
    if actual + 0.005 < expected { failed = true }
}
if failed { fputs("Swift 覆盖率低于基线。\n", stderr); exit(1) }
