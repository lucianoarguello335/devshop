# Diagnose and fix my macOS development environment

You are helping me repair issues on my Mac's development environment. The findings below were produced by DevShop, a read-only scanner that inspects the filesystem directly — it reads Homebrew's Cellar and Caskroom, application bundles, and the version directories under nvm, pyenv and rbenv. It never runs package managers and never changes anything, so treat every finding as an observation, not an action already taken.

Scan taken 3 Sep 2026 at 13:19. 8 findings: 1 error · 4 warnings · 3 notes.

## Machine
- MacBookPro18,1
- Apple M1 Pro · 32 GB
- macOS 26.6.2 · arm64
- Disk: 249.06 GB used, 745.60 GB free

## Toolchain and how it is managed
- Homebrew: 149 formulae, 52 casks
  - 15 formulae keep more than one version directory: agent-browser, fastfetch, gh, gnupg, go, idb-companion, mole, openssl@3, pcre2, pyenv
- Ruby is installed 3 times:
  - 3.2.2 · rbenv at ~/.rbenv/versions/3.2.2
  - 3.3.0 · rbenv at ~/.rbenv/versions/3.3.0
  - 3.3.8 · rbenv at ~/.rbenv/versions/3.3.8
- Package and version managers present: Bundler (system), Homebrew (149 formulae · 52 casks), Maven (3.9.16 · Homebrew), RubyGems (system), SDKMAN! (installed), Swift Package Manager (Apple toolchain), bun (1.3.9 · Homebrew), npm (installed · Homebrew), nvm (1 version installed), pip (3.14.7), poetry (installed), pyenv (1 version installed), rbenv (3 versions installed), uv (0.12.9 · Homebrew)
- Not installed (relevant if a fix suggests one): .NET, AWS CLI, Android SDK, Android Studio, Ansible, Azure CLI, Clojure, CocoaPods, Colima, Composer, Crystal, Dart / Flutter

## Findings

### 1. [ERROR] Ruby 3.2 is past end of life
- Area: Languages & Runtimes · Ruby
- What the scanner saw: Security support ended 6 months ago. Managed by rbenv — a newer line can be installed alongside.
- Affected:
  - Ruby — 3.2.2 · rbenv, at `~/.rbenv/versions/3.2.2`, managed by rbenv, using 237 MB

### 2. [WARNING] 15 Homebrew formulae keep old versions
- Area: Homebrew · Formulae
- What the scanner saw: agent-browser, fastfetch, gh and 12 more each have more than one version directory in the Cellar. `brew cleanup` reclaims the older copies.
- Affected:
  - Formulae — 149 installed, at `/opt/homebrew/Cellar`, managed by Homebrew, using 6.18 GB
    - contains llvm@22 22.1.8 (1.59 GB)
    - contains gcc 16.2.0 (519 MB)
    - contains pytorch 2.13.0_3 (513 MB)
    - contains openjdk 26.0.2.1 (398 MB)
    - contains go 1.27.1 (283 MB)

### 3. [WARNING] Node.js 22 reaches end of life in 6 months
- Area: Languages & Runtimes · Node.js
- What the scanner saw: Managed by nvm — a newer line can be installed alongside.
- Affected:
  - Node.js — 22.19.0 · nvm, at `~/.nvm/versions/node/v22.19.0`, managed by nvm, using 380 MB

### 4. [WARNING] Python 3.11 reaches end of life in 12 months
- Area: Languages & Runtimes · Python
- What the scanner saw: Managed by pyenv — a newer line can be installed alongside.
- Affected:
  - Python — 3.11.6 · pyenv, at `~/.pyenv/versions/3.11.6`, managed by pyenv, using 489 MB

### 5. [WARNING] Ruby 3.3 reaches end of life in 5 months
- Area: Languages & Runtimes · Ruby
- What the scanner saw: Managed by rbenv — a newer line can be installed alongside.
- Affected:
  - Ruby — 3.3.0 · rbenv, at `~/.rbenv/versions/3.3.0`, managed by rbenv, using 411 MB
  - Ruby — 3.3.8 · rbenv, at `~/.rbenv/versions/3.3.8`, managed by rbenv, using 292 MB

### 6. [INFO] 3 Ruby versions installed
- Area: Languages & Runtimes · Ruby
- What the scanner saw: 3.2.2, 3.3.0, 3.3.8 are all present. Older lines can be removed once no project pins them.
- Affected:
  - Ruby — 3.2.2 · rbenv, at `~/.rbenv/versions/3.2.2`, managed by rbenv, using 237 MB
  - Ruby — 3.3.0 · rbenv, at `~/.rbenv/versions/3.3.0`, managed by rbenv, using 411 MB
  - Ruby — 3.3.8 · rbenv, at `~/.rbenv/versions/3.3.8`, managed by rbenv, using 292 MB

### 7. [INFO] No container runtime is installed
- Area: IDEs & Dev Tools · Containers
- What the scanner saw: Docker Desktop, OrbStack, Podman and Colima are all absent. Anything with a Dockerfile or a devcontainer will not run locally.
- Affected:
  - Docker Desktop — no container runtime, managed by —
  - OrbStack — not present, managed by —
  - Podman — not present, managed by —
  - Colima — not present, managed by —

### 8. [INFO] Rosetta 2 is still installed
- Area: Shell & Core Tooling · Rosetta 2
- What the scanner saw: x86_64 translation stays on disk once installed. Some casks still need it, so removing it is only safe when nothing Intel-only is left.
- Affected:
  - Rosetta 2 — x86_64 translation, at `/Library/Apple/usr/share/rosetta`, managed by Manual install, using 4 KB

## What I need from you

Start with the 1 error — those are the ones already causing a problem rather than warning about a future one.

For **each** finding above, work through:

1. **Root cause** — what actually produced this state, not just a restatement of the finding. If the scanner's reading could be a false positive, say so and tell me how to confirm it.
2. **Risk of fixing** — what could break, which projects or shells would notice, and whether anything else depends on the current state.
3. **Risk of leaving it** — be concrete about the consequence and the timescale. If the honest answer is "almost none", say that instead of manufacturing urgency.
4. **Blast radius** — global vs per-project, reversible vs not, and whether it touches anything outside my home directory.

Then give me:

- An **ordered plan** across all findings, grouped so I can do it in one sitting, with anything that must happen before something else called out explicitly.
- **Exact commands** for each step, copy-pasteable, with the working directory when it matters. No placeholders I have to guess at.
- A **verification step** per fix — the specific command and the output that proves it worked.
- A **rollback** per fix, or an explicit note that a step cannot be undone.
- Anything I should **back up or note down first**, especially version numbers that projects may pin.

Finally, tell me which findings you would **deliberately skip**, and why. I would rather leave something alone than churn my environment for a marginal gain.

## Constraints

- Do not assume you can run anything. Give me commands and I will run them.
- Flag any command that deletes data, changes a global default, or needs `sudo` before I reach it, and explain what it will affect.
- This is Apple silicon with Homebrew at `/opt/homebrew`. Do not give me `/usr/local` paths or Intel-only advice.
- Runtimes are managed by version managers, not just Homebrew. Check which one owns a tool before proposing an upgrade path.
- Ask before removing any runtime version — a project may pin it even if nothing on this machine shows that.
- If a finding is better solved by changing how I work rather than by a command, say so.
