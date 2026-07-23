#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const [component, reportPath, baselinePath, command] = process.argv.slice(2);
if (!["backend", "frontend"].includes(component) || !reportPath || !baselinePath) {
  console.error("用法：check-coverage.mjs backend|frontend REPORT BASELINE [--update]");
  process.exit(2);
}

const root = resolve(import.meta.dirname, "..");
const baseline = existsSync(baselinePath)
  ? JSON.parse(readFileSync(baselinePath, "utf8"))
  : { schema_version: 1, backend: {}, frontend: {} };
const current = component === "backend"
  ? backendCoverage(reportPath)
  : frontendCoverage(reportPath);

const globalMinimum = component === "backend"
  ? { statements: 78, branches: 70, functions: 83, lines: 85 }
  : { lines: 61, regions: 52, functions: 56 };
const newFileMinimum = component === "backend"
  ? { statements: 80, branches: 70, functions: 80, lines: 80 }
  : { lines: 80, regions: 70, functions: 80 };

if (command === "--update") {
  baseline[component] = current.files;
  writeFileSync(baselinePath, `${JSON.stringify(baseline, null, 2)}\n`);
  console.log(`已更新 ${component} 覆盖率基线。`);
  process.exit(0);
}

const failures = [];
checkMinimum("总体", current.total, globalMinimum, failures);
for (const [file, metrics] of Object.entries(current.files)) {
  const prior = baseline[component]?.[file];
  if (!prior) {
    checkMinimum(`新增文件 ${file}`, metrics, newFileMinimum, failures);
    continue;
  }
  for (const [name, value] of Object.entries(metrics)) {
    if (value + 0.25 < Number(prior[name] ?? 0)) {
      failures.push(`${file} ${name} 从 ${prior[name]}% 降至 ${value}%`);
    }
  }
}
for (const file of Object.keys(baseline[component] ?? {})) {
  if (!current.files[file]) failures.push(`覆盖率报告缺少既有源码：${file}`);
}

if (failures.length) {
  console.error(["覆盖率门禁失败：", ...failures.map((value) => `- ${value}`)].join("\n"));
  process.exit(1);
}
console.log(`${component} 覆盖率门禁通过。`);

function checkMinimum(label, actual, minimum, failures) {
  for (const [name, value] of Object.entries(minimum)) {
    if (Number(actual[name] ?? 0) < value) {
      failures.push(`${label} ${name} 为 ${actual[name] ?? 0}%，低于 ${value}%`);
    }
  }
}

function backendCoverage(path) {
  const data = JSON.parse(readFileSync(path, "utf8"));
  const files = {};
  for (const [filename, summary] of Object.entries(data)) {
    if (filename === "total") continue;
    const relative = filename.replace(`${root}/backend/`, "");
    if (!relative.startsWith("src/")) continue;
    files[relative] = backendMetrics(summary);
  }
  return { total: backendMetrics(data.total), files };
}

function backendMetrics(summary) {
  return Object.fromEntries(
    ["statements", "branches", "functions", "lines"]
      .map((name) => [name, Number(summary[name].pct)]),
  );
}

function frontendCoverage(path) {
  const data = JSON.parse(readFileSync(path, "utf8")).data[0];
  const files = {};
  const counts = {
    lines: { covered: 0, count: 0 },
    regions: { covered: 0, count: 0 },
    functions: { covered: 0, count: 0 },
  };
  for (const value of data.files) {
    const prefix = `${root}/frontend/`;
    if (!value.filename.startsWith(`${prefix}Sources/`)) continue;
    const relative = value.filename.slice(prefix.length);
    files[relative] = frontendMetrics(value.summary);
    for (const name of Object.keys(counts)) {
      counts[name].covered += value.summary[name].covered;
      counts[name].count += value.summary[name].count;
    }
  }
  const total = Object.fromEntries(Object.entries(counts).map(([name, value]) => [
    name,
    value.count === 0 ? 0 : round(value.covered / value.count * 100),
  ]));
  return { total, files };
}

function frontendMetrics(summary) {
  return Object.fromEntries(
    ["lines", "regions", "functions"]
      .map((name) => [name, round(Number(summary[name].percent))]),
  );
}

function round(value) {
  return Math.round(value * 100) / 100;
}
