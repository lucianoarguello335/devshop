# DevShop — App Icon Design Brief

## 1. What the app is

DevShop is a native macOS application, written in SwiftUI, that shows you the entire
development environment installed on your Mac. It is a **viewer and inspector**, not a
package manager: it never installs, updates or removes anything, never runs a shell
command, and never touches the network. It only looks.

On launch it scans the filesystem for about 137 known languages, SDKs, runtimes, package
managers, IDEs and command-line tools — Node, Python, Ruby, Java, Go, Rust, Swift,
Homebrew, Docker, Xcode, VS Code and the rest. It reads each one's real version and path
from disk, groups them into six categories, measures how much disk space each one takes,
and lists everything it knows about but could not find in a separate "Not Installed"
panel.

It then derives **findings**: runtimes past end of life, stale Homebrew versions, two
copies of the same tool where one shadows the other, a missing container runtime. Those
findings roll up into a single **health score** shown as a coloured ring — green when the
machine is healthy, amber when it needs attention, red when there are problems.

Two extra actions define its character: **Copy setup** puts the whole inventory on the
clipboard as clean, diffable JSON, and **Copy AI prompt** puts a full written briefing of
every finding on the clipboard so an AI agent can advise on fixing them.

## 2. What it feels like

- **Diagnostic, not decorative.** It is a health check-up for a developer machine — an
  X-ray, an inventory, a workshop wall of tools.
- **Read-only and calm.** Nothing it does is destructive. There is no urgency, no alarm.
- **Dense but ordered.** Hundreds of items, all sorted, measured and named.
- **Native macOS.** It belongs beside Xcode, Instruments, Activity Monitor and
  Console — Apple's own utility apps.

Words that describe it: inventory, environment, workbench, toolshed, audit, health,
versions, disk space, tidy, precise, offline, honest.

Words that do **not** describe it: cloud, social, playful, cartoon, AI-magic, sparkles,
speed, rockets.

## 3. Current icon (what to improve on)

A single rounded-square macOS tile in muted purple, with a white glyph centred on it.
The glyph is the "code" mark: two angle brackets `< >` with a forward slash between them.

- Tile: rounded square, corner radius 22.5% of the tile, occupying 824 of a 1024 canvas,
  soft drop shadow beneath.
- Gradient: top-left `#8F83BC` (light dusty purple) to bottom-right `#675B90`
  (deeper muted purple), diagonal.
- Glyph: pure white, about 50% of the tile width, centred, flat, no bevel or gloss.

It is clean but generic — `</>` says "code editor", not "environment inventory". The new
icon should say something more specific about *surveying* or *taking stock of* a
development machine.

## 4. Design constraints (macOS app icon, non-negotiable)

- **Shape:** one rounded square ("squircle"), the standard macOS app-icon silhouette.
  Nothing may break outside it except a very soft contact shadow.
- **Canvas:** square, 1024 × 1024. The tile itself fills roughly 80% of the canvas,
  centred, with even margin around it.
- **Corner radius:** approximately 22.5% of the tile's own width.
- **Flat and modern:** no skeuomorphism, no glass reflection, no bevel, no outer glow,
  no text, no letters, no words, no numbers.
- **Front-facing:** straight on, no perspective, no tilt, no 3-D room.
- **Single focal subject:** one clear shape or a small tight cluster — not a scene.
- **Legible at 16 × 16 pixels.** This is the hardest rule. Thick strokes, high contrast,
  large negative space, at most two or three distinct elements.
- **Solid or simply-gradiented background inside the tile.** No photographic texture,
  no noise, no busy pattern.

## 5. Colour direction

Keep the purple identity, or push it:

- Primary: muted purple, `#8F83BC` → `#675B90`, diagonal gradient.
- The glyph or subject sits in white or near-white (`#F2F2F7`) for maximum contrast.
- Optional single accent, used sparingly: system blue `#0A84FF`, or a health-ring
  green / amber if the health idea is used.
- Avoid: neon, rainbow gradients, more than two hues in the background.

## 6. Concept directions to explore

Any one of these, rendered as a single flat macOS tile:

1. **The health ring.** A thick circular ring, three-quarters closed, drawn in white or
   green on the purple tile, with a small simple glyph at its centre. Says "score",
   "check-up", "status at a glance".
2. **The inventory grid.** A neat 3 × 3 or 2 × 2 grid of small rounded squares of
   varying fill — some solid, some outlined — suggesting an ordered catalogue of
   installed tools. Says "everything you have, sorted".
3. **The stack of versions.** Three or four horizontal rounded bars of decreasing width,
   stacked, like a bar chart or a size meter. Says "measured", "how much disk".
4. **The magnifier over the tile.** A bold, simple magnifying glass whose lens contains
   a tiny grid or `</>` mark. Says "inspector", "read-only look". Keep the handle thick.
5. **The toolbox / shed.** A very simplified toolbox or workbench silhouette in white.
   Says "dev shop" literally. Risk: it can look like a generic hardware app — keep it
   geometric, not illustrative.
6. **Nested boxes.** Two or three concentric rounded outlines, largest to smallest,
   suggesting containers within containers — Homebrew inside the Cellar, packages inside
   a manager. Says "what's inside what".
7. **The refined `</>`.** Keep the existing angle brackets but add one distinguishing
   element — a ring around them, a small check mark, or a subtle scan line — so it reads
   as *inspecting* code rather than *writing* it.

## 7. Prompt template

Use this as the base and swap the concept sentence:

> A macOS app icon. A single rounded square tile (squircle) with a corner radius of about
> 22% of its width, centred on a transparent square canvas with even margins and a soft
> drop shadow beneath the tile. The tile is filled with a smooth diagonal gradient from
> muted dusty purple #8F83BC at the top-left to deeper purple #675B90 at the bottom-right.
> Centred on the tile, at about 50% of the tile's width, is **[CONCEPT]**, drawn in pure
> flat white with thick, even strokes and generous negative space. Completely flat vector
> style — no bevel, no gloss, no reflection, no 3-D, no texture, no shadow on the glyph
> itself. No text, no letters, no numbers, no words anywhere. Clean, geometric, minimal,
> Apple-utility aesthetic. Must stay legible when scaled down to 16 pixels.

Example `[CONCEPT]` fills:

- "a thick open circular ring, three-quarters complete, with a small solid square at its centre"
- "a neat three-by-three grid of small rounded squares, four of them solid and five of them outlined"
- "four stacked horizontal rounded bars of decreasing length, like a bar chart"
- "a bold magnifying glass seen straight on, its round lens containing a small two-by-two grid of squares"
- "three concentric rounded-square outlines, one inside the next"

## 8. Deliverable

A single square PNG, 1024 × 1024, transparent outside the tile. It will be down-sampled
to 512, 256, 128, 64, 32 and 16 pixels for the `.icns` bundle, so check the 16-pixel
version before choosing.
