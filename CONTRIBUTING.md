# Contributing to DevShop

Thanks for looking. The most useful contribution is almost always **adding a tool DevShop missed
on your machine** — and that does not require writing any Swift.

---

## Adding a tool (no Swift required)

The tool catalog is data, not code. `Sources/DevShop/Catalog/catalog.json` lists every tool
DevShop knows about and how to find it. Adding one is a JSON edit:

1. Open `Sources/DevShop/Catalog/catalog.json`
2. Copy an existing entry from the same category and adapt it. An entry looks like this:

   ```json
   {
    "id": "lang.swift",
    "name": "Swift",
    "category": "lang",
    "icon": "swift",
    "symbol": "swift",
    "color": "f05138",
    "website": "https://swift.org",
    "rules": [
     { "kind": "executable", "names": ["swift"] },
     { "kind": "directory", "path": "/Library/Developer/CommandLineTools/usr/bin/swift" }
    ],
    "missingNote": null
   }
   ```

   `rules` is how DevShop finds the tool — list every plausible location, most specific first.
   `icon` is a [Simple Icons](https://simpleicons.org) slug, `symbol` is the SF Symbol fallback,
   `color` is the brand hex without the `#`.
3. Run `make run` and confirm your tool appears with a real version and path
4. Open a pull request

If the tool writes its version somewhere unusual, it may also need a reader in
`Sources/DevShop/Scan/VersionReaders.swift`. Open the PR anyway and say so — a catalog entry that
shows a dash is still better than no entry, and the reader can be added on top.

**Brand marks** come from [Simple Icons](https://simpleicons.org). If your tool has one, add its
slug — `Scripts/fetch-icons.sh` pulls the path data into `icons.json`. Tools without a mark fall
back to an SF Symbol, which is fine.

## Reporting a detection bug

Wrong version, wrong path, missing tool, or a finding that is not true? Open an issue and include:

```bash
DEVSHOP_DUMP=1 ./DevShop.app/Contents/MacOS/DevShop
```

That prints what the probes actually found, with no window. Paste the relevant lines. Redact
anything you would rather not share — DevShop masks secrets, but the dump is yours to review.

## What DevShop will not accept

These are hard constraints, not preferences. A PR that breaks one of them will not be merged:

- **No subprocesses and no shells.** Detection is filesystem reads. Never `Process`, never a shell
  invocation, never sourcing a dotfile.
- **No network access.** End-of-life data is a bundled table. No version APIs.
- **No writes to the user's system.** DevShop reads. It does not install, update, remove or
  modify anything outside its own Application Support directory.
- **No emoji in the interface.** Brand marks or SF Symbols only.

The reasoning behind each is in [docs/design-notes.md](docs/design-notes.md).

## Style

Match the surrounding code. `AppModel` is the single `@MainActor @Observable` source of truth;
`EnvironmentScanner` and `SizeMeasurer` are actors, so nothing touching the filesystem runs on the
main thread. Keep it that way.

---

## Build

```bash
make run          # release build, wrap into DevShop.app, launch
make test         # unit tests
make app          # build the bundle without launching
```

### Cutting a release

```bash
make release                  # universal, signed, notarized, stapled -> dist/
make release ARGS=--dry-run   # rehearse the whole thing without a certificate
```

It writes two identical images: `DevShop-<version>.dmg` and `DevShop.dmg`. **Attach both to the
release.** GitHub's `/releases/latest/download/<name>` shortcut needs a constant filename, and the
website links the version-less one, so that URL never has to be edited again.

`VERSION` is the single source of truth for the version string, the DMG filename and the git
tag. `CFBundleVersion` comes from the commit count, so there is no second number to bump.

A release needs two things on the build machine, both one-time:

- A **Developer ID Application** certificate in the keychain. Xcode creates it: Settings >
  Accounts > *team* > Manage Certificates > **+** > Developer ID Application.
- A notarization credential named `devshop-notary`:

  ```bash
  xcrun notarytool store-credentials devshop-notary --apple-id <you> --team-id <team>
  ```

  The password is an [app-specific password](https://support.apple.com/en-us/HT204397), not
  the Apple Account password.

The first build needs nothing but the Swift toolchain shipped with Xcode. `icons.json` and
`catalog.json` are committed, so `make icons` and `make catalog` are only needed when you
change the icon list or the tool catalog.
