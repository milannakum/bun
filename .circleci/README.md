# CircleCI (fork release builds)

CircleCI only reads **one** top-level config (`.circleci/config.yml`). That file is a **setup workflow**: when you trigger with **`run_pipeline=true`**, it checks out the repo, runs `assemble-config.sh`, writes **`.circleci/merged-config.yml`**, then uses the **`circleci/continuation`** orb to run the assembled pipeline. **Plain pushes/tags** (`run_pipeline` defaults to `false`) run **no workflows and no jobs** in this config, so you do not pay Docker executor minutes for a no-op skip step. If you still want **no CircleCI run at all** on push (no pipeline row in the UI), disable automatic builds in **CircleCI Project Settings** (or use org-level policies) in addition to this.

**Edit the fragments**, not `merged-config.yml` (it is gitignored and regenerated every run).

## Layout

| Path | Purpose |
|------|---------|
| `config.yml` | Setup workflow: checkout → merge → `continuation/continue` |
| `assemble-config.sh` | Concatenates fragments into `merged-config.yml` |
| `parts/00-version-and-parameters.yml` | `version` + pipeline `parameters` |
| `parts/10-commands.yml` | Shared `commands:` (checkout ref, Bun install, target flags) |
| `linux/build-linux-gnu.job.yml` | Linux GNU `docker` job (official [bun-development-docker-image](https://github.com/oven-sh/bun-development-docker-image)) |
| `macos/build-macos-arm64.job.yml` | macOS Apple Silicon job definition |
| `publish/publish-github-release.job.yml` | Optional GitHub Release upload job |
| `workflows/bun-release.yml` | `workflows:` (job graph, filters, `requires`) |

## What runs

- `linux-x64-gnu`, `linux-x64-gnu-baseline` on a Linux **`docker` executor** using **`ghcr.io/oven-sh/bun-development-docker-image:latest`** ([`oven-sh/bun-development-docker-image`](https://github.com/oven-sh/bun-development-docker-image)). The job runs **`scripts/bootstrap.sh`** from your checked-out tree so toolchain versions track the commit (the image provides a preconfigured Debian environment + Bun; do **not** use `:prebuilt` / `:run` tags here — they override `ENTRYPOINT` for `bun-debug`). **CircleCI Free** supports the Docker executor; this is usually cheaper/simpler than `machine` for Linux.
- `darwin-aarch64` on a hosted Apple Silicon macOS executor (`macos.m1.medium.gen1`), but it is **disabled by default** via pipeline parameter `run_macos_build=false` for free-plan compatibility.

For CircleCI Free, keep `run_macos_build=false` unless your project explicitly has hosted macOS access enabled.

Intel macOS targets (`darwin-x64`, `darwin-x64-baseline`) are **not** included here: full Bun builds need host == target for C++/JSC, and CircleCI’s hosted macOS fleet is Apple Silicon. Keep Intel mac builds on GitHub Actions (`macos-13`) or a self-hosted Intel Mac.

## Local validation

```bash
bash .circleci/assemble-config.sh
circleci config validate .circleci/merged-config.yml
```

## Manual trigger (like workflow_dispatch)

This setup is now **manual by default**:

- `run_pipeline=false` by default, so push/tag pipelines do not run build jobs unless you opt in.
- Select targets with booleans:
  - `run_linux_x64_gnu` (default `true`)
  - `run_linux_x64_gnu_baseline` (default `false`)
  - `run_macos_build` (default `false`, free-plan friendly)
- Choose commit/branch/tag/SHA with `build_ref`.

Typical manual trigger examples:

- Linux only: `run_pipeline=true`, `run_linux_x64_gnu=true`, `run_linux_x64_gnu_baseline=false`, `run_macos_build=false`
- Linux + baseline: `run_pipeline=true`, `run_linux_x64_gnu=true`, `run_linux_x64_gnu_baseline=true`, `run_macos_build=false`
- Full (if macOS is enabled on your plan): set all three target flags to `true`.

## Optional: GitHub Release upload

1. Create a **GitHub Release** for the tag (empty is fine) if needed.
2. CircleCI **Project Settings → Environment Variables**: `GITHUB_TOKEN` with `contents:write`.
3. Trigger a **tag** pipeline with pipeline parameter **`upload_github_release=true`**.

## Optional: build a different commit

Trigger with pipeline parameter **`build_ref`** = branch, tag, or SHA (see `checkout_build_ref` command).

## Caches

- **Linux**
  - `~/.cargo/registry`, `~/.cargo/git`, `~/.rustup` — bootstrap / Rust toolchain reuse (`linux-bootstrap-v1-*`, keyed by `scripts/bootstrap.sh` checksum).
  - `build/circleci-<target>/cache` — Bun **vendor** downloads (WebKit prebuilt, Node headers, **ccache**, etc.).
- **macOS**
  - `~/Library/Caches/Homebrew` — bottle downloads.
  - `~/.bun` — same as Linux.
  - `build/circleci-<target>/cache` — same Bun build cache.

**Vendor / dep cache key** includes `bun.lock`, `scripts/build/deps/{webkit,nodejs-headers,boringssl,libarchive}.ts`, and `scripts/build/zig.ts`, plus **restore fallback** prefixes so partial hits still help.

Bump `v1` / `v2` suffixes in cache keys if a cache goes stale after image or script changes.

## If your org disallows dynamic config

You can run `assemble-config.sh` locally, commit the generated `merged-config.yml`, and temporarily point CircleCI at a static config (not recommended long term—drift risk). Prefer keeping the setup + merge flow.
