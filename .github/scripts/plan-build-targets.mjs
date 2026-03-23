#!/usr/bin/env node
/**
 * Resolves which Bun release targets to build for .github/workflows/build.yml.
 * Writes counts + JSON matrices to GITHUB_OUTPUT (one row per matrix.include entry).
 *
 * Target ids match oven-sh/bun release zips (bun-<triplet>.zip), using hyphens in ids.
 *
 * Linux musl variants are omitted here: they expect an Alpine/musl host (see upstream
 * BuildKite). This workflow uses standard GitHub-hosted runners only (no job containers).
 */
import { appendFileSync } from "node:fs";

/** @typedef {{ id: string, family: "linux-gnu"|"darwin"|"windows", runs_on: string, os: string, arch: string, abi?: string, baseline: boolean, artifact_triplet: string }} Target */

/** @type {Target[]} */
const ALL = [
  {
    id: "linux-x64-gnu",
    family: "linux-gnu",
    runs_on: "ubuntu-latest",
    os: "linux",
    arch: "x64",
    abi: "gnu",
    baseline: false,
    artifact_triplet: "bun-linux-x64",
  },
  {
    id: "linux-x64-gnu-baseline",
    family: "linux-gnu",
    runs_on: "ubuntu-latest",
    os: "linux",
    arch: "x64",
    abi: "gnu",
    baseline: true,
    artifact_triplet: "bun-linux-x64-baseline",
  },
  {
    id: "linux-aarch64-gnu",
    family: "linux-gnu",
    runs_on: "ubuntu-24.04-arm64",
    os: "linux",
    arch: "aarch64",
    abi: "gnu",
    baseline: false,
    artifact_triplet: "bun-linux-aarch64",
  },
  {
    id: "darwin-x64",
    family: "darwin",
    runs_on: "macos-13",
    os: "darwin",
    arch: "x64",
    baseline: false,
    artifact_triplet: "bun-darwin-x64",
  },
  {
    id: "darwin-x64-baseline",
    family: "darwin",
    runs_on: "macos-13",
    os: "darwin",
    arch: "x64",
    baseline: true,
    artifact_triplet: "bun-darwin-x64-baseline",
  },
  {
    id: "darwin-aarch64",
    family: "darwin",
    runs_on: "macos-14",
    os: "darwin",
    arch: "aarch64",
    baseline: false,
    artifact_triplet: "bun-darwin-aarch64",
  },
  {
    id: "windows-x64",
    family: "windows",
    runs_on: "windows-latest",
    os: "windows",
    arch: "x64",
    baseline: false,
    artifact_triplet: "bun-windows-x64",
  },
  {
    id: "windows-x64-baseline",
    family: "windows",
    runs_on: "windows-latest",
    os: "windows",
    arch: "x64",
    baseline: true,
    artifact_triplet: "bun-windows-x64-baseline",
  },
  {
    id: "windows-aarch64",
    family: "windows",
    runs_on: "windows-11-arm",
    os: "windows",
    arch: "aarch64",
    baseline: false,
    artifact_triplet: "bun-windows-aarch64",
  },
];

function setOutput(name, value) {
  const out = process.env.GITHUB_OUTPUT;
  if (!out) {
    console.error("GITHUB_OUTPUT is not set");
    process.exit(1);
  }
  appendFileSync(out, `${name}=${value}\n`);
}

function parseSelectedIds() {
  const event = process.env.GITHUB_EVENT_NAME || "";
  const buildAllRaw = (process.env.INPUT_BUILD_ALL || "").toLowerCase();
  const buildAll = buildAllRaw === "true" || buildAllRaw === "1";
  const dispatchTargets = (process.env.INPUT_TARGETS || "").trim();
  const releaseDefaults = (process.env.BUN_FORK_RELEASE_TARGETS || "linux-x64-gnu").trim();

  if (event === "workflow_dispatch") {
    if (buildAll || dispatchTargets.toLowerCase() === "all") {
      return ALL.map(t => t.id);
    }
    return dispatchTargets
      .split(",")
      .map(s => s.trim())
      .filter(Boolean);
  }

  // release (published): repository variable BUN_FORK_RELEASE_TARGETS or default
  if (releaseDefaults.toLowerCase() === "all") {
    return ALL.map(t => t.id);
  }
  return releaseDefaults
    .split(",")
    .map(s => s.trim())
    .filter(Boolean);
}

/** @type {Set<string>} */
const REMOVED_IDS = new Set(["linux-x64-musl", "linux-x64-musl-baseline", "linux-aarch64-musl"]);

function main() {
  const selected = parseSelectedIds();
  const removed = selected.filter(id => REMOVED_IDS.has(id));
  if (removed.length) {
    console.error(
      "Linux musl targets are not built on GitHub-hosted runners in this workflow (no job containers):",
      removed.join(", "),
    );
    console.error("Remove them from targets / BUN_FORK_RELEASE_TARGETS, or use a custom musl job.");
    process.exit(1);
  }

  const validIds = new Set(ALL.map(t => t.id));
  const unknown = selected.filter(id => !validIds.has(id));
  if (unknown.length) {
    console.error(`Unknown target id(s): ${unknown.join(", ")}`);
    console.error(`Valid ids: ${[...validIds].sort().join(", ")}`);
    process.exit(1);
  }

  const picked = ALL.filter(t => selected.includes(t.id));
  const byFamily = fam => picked.filter(t => t.family === fam);

  const linuxGnu = byFamily("linux-gnu");
  const darwin = byFamily("darwin");
  const windows = byFamily("windows");

  setOutput("linux_gnu_count", String(linuxGnu.length));
  setOutput("darwin_count", String(darwin.length));
  setOutput("windows_count", String(windows.length));

  setOutput("linux_gnu_matrix", JSON.stringify(linuxGnu));
  setOutput("darwin_matrix", JSON.stringify(darwin));
  setOutput("windows_matrix", JSON.stringify(windows));

  console.log("Selected targets:", picked.map(t => t.id).join(", ") || "(none)");
}

main();
