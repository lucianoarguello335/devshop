# DevShop — Design Notes

Why DevShop is built the way it is. These are the decisions that shaped the app: what it refuses
to do, what that costs, and what it buys.

← Back to the [README](../README.md) · [Download DevShop](https://github.com/lucianoarguello335/devshop/releases/latest)

---

## Detection

**Detection is filesystem-only.** Running `node -v`, `brew list` and friends across 137 tools
would mean well over a hundred process spawns per scan. Reading `Cellar/<formula>/<version>`
and `Contents/Info.plist` gives the same versions for almost every tool, instantly, with no
shell involved.

**The Version column only ever shows a version.** Detection produces two separate things: a
`version` — a bare number and nothing else — and a `subtitle`, which is the descriptive line
tiles show (`147 formulae · 52 casks`, `1 version installed`). The table's Version column
reads the first and shows a dash when no file on disk states one, so a description never
stands in for a number. `VersionReaders` knows the one file each awkward tool writes its
version into: `package.json` for npm, a `dist-info` directory name for pip and poetry, the
literal in `nvm.sh`, the tag `.git/HEAD` points at for Homebrew, a default gemspec's filename
for Bundler, the `swift-compiler-version` header of a shipped `.swiftinterface` for Swift, and
the versioned library directory for zsh, Perl and Ruby. Anything still unnamed falls back to
the Homebrew formula of the same name, then to a `<name>-config` script, then to the `.TH`
header of the tool's own man page — which is how bash, curl and git get a version at all.
All filesystem reads — the no-subprocess rule holds.

The order of those last two matters: macOS ships a `curl.1` that says 8.6.0 next to a curl
binary that is 8.7.1, while `curl-config` carries the real number as a literal, so the config
script is tried first. A man page is the last resort precisely because it states the version
the page was written for. What no file names — jq, oh-my-zsh, powerlevel10k, Rosetta — shows
a dash, which is the honest answer.

**A binary in a shared bin directory is measured, not skipped.** Walking `/usr/bin` would
attribute every neighbour to one tool, so tools there used to report no footprint at all. They
now measure the executable itself and say so: the inspector labels it `binary only`, because
the number is real but covers the binary and not the toolchain it shares.

## Measurement

**Sizes are measured on Refresh, not on launch.** Walking `/Applications/Xcode.app` and the
Homebrew Cellar means visiting hundreds of thousands of files. That work runs only when you
press Refresh (and once on a first launch), streams results in as each root finishes, and
persists to `~/Library/Application Support/DevShop/sizes.json` so later launches are instant.

## Findings, shell config and secrets

**Findings are computed offline.** End-of-life dates come from a small bundled table in
`Findings/Rules.swift` rather than a version API. Refresh that table when release schedules
move — it is the honest source, and it is why the app needs no network access.

**The startup chain is read, never run.** `Scan/ShellConfigReader.swift` parses the zsh chain
as text — `/etc/zshenv`, `~/.zshenv`, `/etc/paths` and `/etc/paths.d/*`, the two `zprofile`s,
the two `zshrc`s, `~/.zlogin` — and follows `source` exactly one level into files that exist.
Running the dotfiles would give perfect answers and would also execute arbitrary code inside a
read-only inspector, so it does not. The cost is that what a framework defines behind
`source $ZSH/oh-my-zsh.sh`, or what an `eval` prints, is reported as the hook that produces it
rather than as its result — which is the line a user can actually edit anyway. One level is
also where it stops being useful: following every `source` pulls in the three hundred files
oh-my-zsh loads, and a sourced file's own `setopt`s and functions are filtered out for the
same reason.

**PATH is resolved, not run.** `Scan/PathResolver.swift` answers "which `python3` runs here" for
two contexts: a new Terminal window, and a login shell started from one that already built PATH
(an editor's terminal, tmux). The reader records every PATH statement in run order — prepend,
append or replace, inside a condition or not, guarded by an "already on PATH" test or not — with
sourced files spliced in at the line that sources them. The resolver replays those steps from
launchd's default PATH, then replays them again on top of the result for the nested shell.
`path_helper` is modelled rather than run, because its rule is fixed: `/etc/paths`, then
`/etc/paths.d` in numeric order, then whatever PATH already held. That second pass is where the
two contexts split: path_helper moves inherited directories behind `/usr/bin`, and a guarded
prepend then declines to add them again. What stops certainty is an `eval` or a `source` that
was not read. It is kept as a slot at its position, and any lookup that passes it is marked
uncertain instead of guessed — and is never reported as a finding. Running `zsh -ilc 'whence
python3'` would give exact answers and would execute the user's dotfiles to get them.

**Secrets are masked, and stay masked in exports.** A value whose name or shape says
credential is shown as `AIza••••••••••DpdA` with a click-to-reveal in the inspector, raises an
error-tier finding, and is written to the setup JSON and the AI prompt in its masked form
only. A path is never treated as a secret: `SSH_KEY_PATH=~/.ssh/id_ed25519` is a location, and
hiding it would remove the only useful part.

## Interface and performance

**The header is the title bar.** The design puts the window controls, title, search and
Refresh on one 52pt row. Getting there on macOS 26 took three things, all in
`UI/Chrome/WindowChrome.swift`: `fullSizeContentView` so content draws at the very top of the
window; `.ignoresSafeArea(edges: .top)` so SwiftUI does not inset below the title bar; and
`toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`, without which the system paints a
translucent panel over the first 32pt and washes out everything under it. AppKit's own title
bar strip is hidden and `WindowControls` draws the close/minimise/zoom buttons — real
controls wired to the window, positioned exactly where the design puts them.

**Derived state is computed on change, not on draw.** `AppModel` stores `visiblePanels`,
`largestToolBytes` and friends and rebuilds them in `rebuildDerived()` when the scan, the
sizes, a filter, a sort or a toggle changes. They used to be computed properties, which meant
the centre column re-filtered and re-sorted every tool eight times per redraw and rescanned
every measurement once per tile — fine at rest, visibly janky while scrolling or resizing.
Size measurements are coalesced into 250 ms batches for the same reason: one publish per
directory walked was ~500 full rebuilds per Refresh.

**The whole scan exports as JSON.** "Copy setup" in the header puts the complete inventory on
the clipboard: machine and OS, a summary with the health score and Homebrew counts, every
category with its tools, each tool's nested contents, and the findings. It exports everything
scanned rather than what is on screen, so the file means the same thing regardless of the
search field or hidden panels. Keys are sorted and the output indented, so two exports — from
different machines, or the same machine months apart — diff cleanly. It also lists every
application bundle, because Finder's "Applications" is a merged view of `/Applications` and
`/System/Applications` — the export reads both and tags each entry `user` or `system`, so
what you installed can be told apart from what macOS ships. Application sizes are omitted on
purpose: walking a hundred-odd bundles would stall a synchronous export.
`docs/example-setup.json` is a real export with the machine's own application
inventory and volume figures replaced by a representative sample — the schema is
unchanged, and the version field at the top makes a future format change detectable.

**Findings can be handed to an AI agent.** "Copy AI prompt" in the Findings header puts a
full briefing on the clipboard — machine, which manager owns which runtime, every finding with
the exact paths, versions and sizes it points at, and for containers the heaviest packages
inside them. It asks for root cause, risk of fixing, risk of *not* fixing, blast radius,
ordered steps, verification and rollback, and explicitly invites the agent to say which
findings to skip. See `docs/example-ai-prompt.md` for real output. ⌘⇧C does the same thing.

**The health ring cannot contradict itself.** Score, caption and ring colour all come from
`HealthStatus` in `Model/HealthStatus.swift`: 100 minus 15 per error, 5 per warning and 1 per
note, clamped, then banded into healthy / mostly healthy / needs attention / problems with a
colour each. The ring was previously hardcoded green, which meant it stayed green while the
text under it read "Needs attention".

**Two layouts, one ordering.** The centre column draws either the tile grid or a sortable
table, switched from the title bar and remembered between launches. Both read the same sort
state, so flipping views never reshuffles anything. Alphabetical is the default; clicking a
column header in list view changes it, and size starts descending because that is what the
question means when someone sorts by it.

**Containers list their contents.** Selecting Formulae, Casks, Taps, npm, pip, a version
manager or the VS Code extensions fills the inspector with what is actually inside, heaviest
first. Casks stage a real `.app`, so their genuine application icon is read straight off disk
with `NSWorkspace` — no guessing a brand from the cask token, and always correct. Formulae and
packages fall back to a brand mark, then to a tinted monogram.

Matching a package to a brand mark takes a cascade rather than a lookup, because package
names rarely equal the brand's slug: an explicit alias first (`codex` is OpenAI's), then the
normalised name, then an npm scope, then the name minus one trailing component so
`claude-code` finds `claude` and `docker-compose` finds `docker`. Only slugs that actually
ship with the app are returned, so a miss draws a monogram rather than nothing. Roughly a
third of Homebrew formulae have no brand mark at all, which is simply true of CLI tools.

**The app icon is generated, not hand-drawn.** `Scripts/render-appicon.swift` draws the
icon — nine tool-coloured swatches on a plain tile — as Core Graphics geometry at all ten
sizes, and `make appicon` packs two `.icns` files: a light tile with deep swatches and a
dark tile with bright ones. Both come from the same geometry, so nothing shifts position
between them; only the tile colour and the nine swatch values differ.

**The Dock icon follows the window, not the system.** Both `.icns` files ship in the
bundle. A bundle names a single `CFBundleIconFile`, so `DevShop.icns` — the light tile — is
what Finder and the Dock show before launch; once running, `UI/Chrome/DockIcon.swift` sets
`applicationIconImage` from the same appearance `RootWindow` draws with, so the icon tracks
the title bar's light/dark switch as well as the system setting. The cost is visible: in
dark mode the tile changes the moment the app opens, and back when it quits. macOS offers
no way around that — an Icon Composer `.icon` cannot vary its layer artwork by appearance
either, and its dark rendition paints a system background rather than the tile's own fill.

**Icons are vector paths, not images.** `Scripts/fetch-icons.sh` pulls each brand mark from
Simple Icons and keeps only its single SVG `<path>` in `icons.json`. `SVGPath.swift` renders
those directly into a SwiftUI `Path`, so 92 marks cost ~174 KB, stay crisp at any size, and
need no asset catalog. Tools with no brand mark fall back to an SF Symbol. No emoji are used
anywhere in the interface.
