#!/usr/bin/env python3
"""Generates Sources/DevShop/Catalog/catalog.json.

Kept as a generator rather than hand-written JSON because the rule shapes repeat heavily
and the list is long. Edit here, re-run, commit both files.
"""
import json, os, sys

def exe(*names):        return {"kind": "executable", "names": list(names)}
def formula(name):      return {"kind": "brewFormula", "name": name}
def cask(name):         return {"kind": "brewCask", "name": name}
def app(*paths):        return {"kind": "appBundle", "paths": list(paths)}
def d(path, version=None):
    r = {"kind": "directory", "path": path}
    if version: r["version"] = version
    return r
def vm(manager):        return {"kind": "versionManager", "manager": manager}

tools = []

def T(id, name, category, color, rules, icon=None, symbol="shippingbox.fill",
      website=None, missing=None):
    tools.append({
        "id": id, "name": name, "category": category, "icon": icon, "symbol": symbol,
        "color": color, "website": website, "rules": rules, "missingNote": missing,
    })

# ---------------------------------------------------------------- Languages & runtimes
L = "lang"
T("lang.swift", "Swift", L, "f05138", [exe("swift"), d("/Library/Developer/CommandLineTools/usr/bin/swift")],
  icon="swift", symbol="swift", website="https://swift.org")
T("lang.python", "Python", L, "3776ab", [vm("pyenv"), formula("python@3.13"), formula("python@3.12"), exe("python3")],
  icon="python", symbol="chevron.left.forwardslash.chevron.right", website="https://python.org")
T("lang.node", "Node.js", L, "43853d", [vm("nvm"), formula("node"), exe("node")],
  icon="nodedotjs", symbol="hexagon.fill", website="https://nodejs.org")
T("lang.ruby", "Ruby", L, "cc342d", [vm("rbenv"), formula("ruby"), exe("ruby")],
  icon="ruby", symbol="diamond.fill", website="https://ruby-lang.org")
T("lang.go", "Go", L, "00add8", [formula("go"), exe("go")],
  icon="go", symbol="figure.run", website="https://go.dev")
T("lang.rust", "Rust", L, "dea584", [d("~/.rustup"), exe("rustc")],
  icon="rust", symbol="gearshape.2.fill", website="https://rust-lang.org", missing="no rustup / cargo")
T("lang.java", "Java", L, "e76f00", [vm("jvm"), formula("openjdk"), exe("java")],
  icon="openjdk", symbol="cup.and.saucer.fill", website="https://openjdk.org")
T("lang.kotlin", "Kotlin", L, "7f52ff", [formula("kotlin"), exe("kotlinc", "kotlin")],
  icon="kotlin", symbol="k.square.fill", website="https://kotlinlang.org", missing="standalone compiler")
T("lang.scala", "Scala", L, "dc322f", [formula("scala"), exe("scala")],
  icon="scala", symbol="s.square.fill", website="https://scala-lang.org")
T("lang.clojure", "Clojure", L, "5881d8", [formula("clojure"), exe("clj", "clojure")],
  icon="clojure", symbol="c.square.fill", website="https://clojure.org")
T("lang.clang", "Clang / GCC", L, "7a5cff", [d("/Library/Developer/CommandLineTools/usr/bin/clang"), exe("clang")],
  icon="c", symbol="c.square.fill", website="https://clang.llvm.org")
T("lang.cpp", "C++", L, "00599c", [d("/Library/Developer/CommandLineTools/usr/bin/clang++"), exe("clang++", "g++")],
  icon="cplusplus", symbol="plus.square.fill", website="https://isocpp.org")
T("lang.gcc", "GNU GCC", L, "a42e2b", [formula("gcc"), exe("gcc-14", "gcc-13")],
  icon="gnu", symbol="cpu.fill", website="https://gcc.gnu.org")
T("lang.dotnet", ".NET", L, "512bd4", [d("/usr/local/share/dotnet"), d("~/.dotnet"), exe("dotnet")],
  icon="dotnet", symbol="square.stack.3d.up.fill", website="https://dotnet.microsoft.com", missing="no SDK")
T("lang.php", "PHP", L, "777bb4", [formula("php"), exe("php")],
  icon="php", symbol="p.square.fill", website="https://php.net", missing="not present")
T("lang.perl", "Perl", L, "0298c3", [exe("perl")],
  icon="perl", symbol="p.circle.fill", website="https://perl.org")
T("lang.lua", "Lua", L, "2c2d72", [formula("lua"), exe("lua")],
  icon="lua", symbol="moon.fill", website="https://lua.org")
T("lang.r", "R", L, "276dc3", [formula("r"), app("/Applications/R.app"), exe("R", "Rscript")],
  icon="r", symbol="r.square.fill", website="https://r-project.org", missing="not present")
T("lang.julia", "Julia", L, "9558b2", [app("/Applications/Julia.app"), formula("julia"), exe("julia")],
  icon="julia", symbol="circle.hexagongrid.fill", website="https://julialang.org")
T("lang.haskell", "Haskell", L, "5d4f85", [d("~/.ghcup"), formula("ghc"), exe("ghc")],
  icon="haskell", symbol="lambda", website="https://haskell.org")
T("lang.ocaml", "OCaml", L, "ec6813", [d("~/.opam"), formula("ocaml"), exe("ocaml")],
  icon="ocaml", symbol="camera.macro", website="https://ocaml.org")
T("lang.elixir", "Elixir", L, "4b275f", [formula("elixir"), exe("elixir")],
  icon="elixir", symbol="drop.fill", website="https://elixir-lang.org", missing="not present")
T("lang.erlang", "Erlang", L, "a90533", [formula("erlang"), exe("erl")],
  icon="erlang", symbol="antenna.radiowaves.left.and.right", website="https://erlang.org")
T("lang.dart", "Dart / Flutter", L, "0175c2", [d("~/development/flutter"), d("~/flutter"), formula("dart"), exe("dart", "flutter")],
  icon="dart", symbol="bird.fill", website="https://dart.dev", missing="no SDK")
T("lang.zig", "Zig", L, "f7a41d", [formula("zig"), exe("zig")],
  icon="zig", symbol="bolt.fill", website="https://ziglang.org")
T("lang.nim", "Nim", L, "ffe953", [formula("nim"), exe("nim")],
  icon="nim", symbol="crown.fill", website="https://nim-lang.org")
T("lang.crystal", "Crystal", L, "000000", [formula("crystal"), exe("crystal")],
  icon="crystal", symbol="sparkles", website="https://crystal-lang.org")
T("lang.v", "V", L, "5d87bf", [formula("vlang"), exe("v")],
  icon="v", symbol="v.square.fill", website="https://vlang.io")
T("lang.groovy", "Groovy", L, "4298b8", [formula("groovy"), exe("groovy")],
  icon="apachegroovy", symbol="g.square.fill", website="https://groovy-lang.org")
T("lang.racket", "Racket", L, "9f1d20", [app("/Applications/Racket"), formula("racket"), exe("racket")],
  icon="racket", symbol="circle.circle.fill", website="https://racket-lang.org")
T("lang.fortran", "Fortran", L, "734f96", [formula("gcc"), exe("gfortran", "gfortran-14")],
  icon="fortran", symbol="function", website="https://fortran-lang.org")
T("lang.typescript", "TypeScript", L, "3178c6", [exe("tsc")],
  icon="typescript", symbol="t.square.fill", website="https://typescriptlang.org")
T("lang.bunrt", "Bun", L, "fbf0df", [formula("bun"), exe("bun")],
  icon="bun", symbol="takeoutbag.and.cup.and.straw.fill", website="https://bun.sh")
T("lang.deno", "Deno", L, "4f4f4f", [formula("deno"), exe("deno")],
  icon="deno", symbol="pawprint.fill", website="https://deno.com")
T("lang.ollama", "Ollama", L, "1f2937", [app("/Applications/Ollama.app"), formula("ollama"), exe("ollama")],
  icon="ollama", symbol="brain", website="https://ollama.com")

# ------------------------------------------------------- Package & version managers
K = "pkg"
T("pkg.homebrew", "Homebrew", K, "fbb040", [d("/opt/homebrew"), d("/usr/local/Homebrew")],
  icon="homebrew", symbol="mug.fill", website="https://brew.sh")
T("pkg.macports", "MacPorts", K, "0b5cab", [d("/opt/local/bin/port")],
  icon="macports", symbol="sailboat.fill", website="https://macports.org", missing="not present")
T("pkg.npm", "npm", K, "cb3837", [exe("npm")],
  icon="npm", symbol="shippingbox.fill", website="https://npmjs.com")
T("pkg.pnpm", "pnpm", K, "f9ad00", [formula("pnpm"), exe("pnpm")],
  icon="pnpm", symbol="cube.box.fill", website="https://pnpm.io")
T("pkg.yarn", "yarn", K, "2c8ebb", [formula("yarn"), exe("yarn")],
  icon="yarn", symbol="circle.grid.cross.fill", website="https://yarnpkg.com")
T("pkg.bun", "bun", K, "f472b6", [formula("bun"), exe("bun")],
  icon="bun", symbol="takeoutbag.and.cup.and.straw.fill", website="https://bun.sh")
T("pkg.pip", "pip", K, "3776ab", [exe("pip3", "pip")],
  icon="pypi", symbol="arrow.down.circle.fill", website="https://pip.pypa.io")
T("pkg.pipx", "pipx", K, "2b579a", [d("~/.local/pipx"), formula("pipx"), exe("pipx")],
  icon="python", symbol="shippingbox.circle.fill", website="https://pipx.pypa.io")
T("pkg.poetry", "poetry", K, "60a5fa", [d("~/Library/pypoetry"), exe("poetry")],
  icon="poetry", symbol="text.book.closed.fill", website="https://python-poetry.org")
T("pkg.uv", "uv", K, "7c3aed", [formula("uv"), exe("uv")],
  icon="uv", symbol="bolt.horizontal.fill", website="https://docs.astral.sh/uv")
T("pkg.conda", "conda", K, "44a833", [d("~/miniconda3"), d("~/anaconda3"), d("/opt/homebrew/Caskroom/miniconda"), exe("conda")],
  icon="anaconda", symbol="circle.circle", website="https://conda.io", missing="not present")
T("pkg.cargo", "cargo", K, "dea584", [d("~/.cargo"), exe("cargo")],
  icon="rust", symbol="shippingbox.fill", website="https://doc.rust-lang.org/cargo", missing="no Rust toolchain")
T("pkg.gem", "RubyGems", K, "e9573f", [exe("gem")],
  icon="rubygems", symbol="diamond.fill", website="https://rubygems.org")
T("pkg.bundler", "Bundler", K, "cc342d", [exe("bundle", "bundler")],
  icon="ruby", symbol="archivebox.fill", website="https://bundler.io")
T("pkg.maven", "Maven", K, "c71a36", [formula("maven"), exe("mvn")],
  icon="apachemaven", symbol="m.square.fill", website="https://maven.apache.org")
T("pkg.gradle", "Gradle", K, "02303a", [d("~/.gradle"), formula("gradle"), exe("gradle")],
  icon="gradle", symbol="g.square.fill", website="https://gradle.org", missing="wrapper-based")
T("pkg.sbt", "sbt", K, "dc322f", [formula("sbt"), exe("sbt")],
  icon="scala", symbol="s.circle.fill", website="https://scala-sbt.org")
T("pkg.cocoapods", "CocoaPods", K, "ee3322", [exe("pod")],
  icon="cocoapods", symbol="cube.box.fill", website="https://cocoapods.org")
T("pkg.spm", "Swift Package Manager", K, "f05138", [exe("swift")],
  icon="swift", symbol="shippingbox.fill", website="https://swift.org/package-manager")
T("pkg.composer", "Composer", K, "885630", [formula("composer"), exe("composer")],
  icon="composer", symbol="music.note.list", website="https://getcomposer.org", missing="no PHP toolchain")
T("pkg.nuget", "NuGet", K, "004880", [d("~/.nuget"), exe("nuget")],
  icon="nuget", symbol="n.square.fill", website="https://nuget.org", missing="no .NET toolchain")
T("pkg.asdf", "asdf", K, "1f2937", [d("~/.asdf"), formula("asdf"), exe("asdf")],
  symbol="square.stack.3d.down.right.fill", website="https://asdf-vm.com", missing="not present")
T("pkg.mise", "mise", K, "6366f1", [d("~/.local/share/mise"), formula("mise"), exe("mise")],
  symbol="dial.high.fill", website="https://mise.jdx.dev", missing="not present")
T("pkg.nvm", "nvm", K, "43853d", [d("~/.nvm")],
  icon="nodedotjs", symbol="arrow.triangle.branch", website="https://github.com/nvm-sh/nvm")
T("pkg.pyenv", "pyenv", K, "3776ab", [d("~/.pyenv")],
  icon="python", symbol="arrow.triangle.branch", website="https://github.com/pyenv/pyenv")
T("pkg.rbenv", "rbenv", K, "cc342d", [d("~/.rbenv")],
  icon="ruby", symbol="arrow.triangle.branch", website="https://github.com/rbenv/rbenv")
T("pkg.jenv", "jenv", K, "e76f00", [d("~/.jenv")],
  icon="openjdk", symbol="arrow.triangle.branch", website="https://jenv.be", missing="not present")
T("pkg.rustup", "rustup", K, "dea584", [d("~/.rustup"), exe("rustup")],
  icon="rust", symbol="arrow.triangle.branch", website="https://rustup.rs", missing="not present")
T("pkg.sdkman", "SDKMAN!", K, "0a97b0", [d("~/.sdkman")],
  symbol="arrow.down.app.fill", website="https://sdkman.io", missing="not present")

# ------------------------------------------------------------------------- Homebrew
B = "brew"
T("brew.formulae", "Formulae", B, "fbb040", [d("/opt/homebrew/Cellar")],
  icon="homebrew", symbol="mug.fill", website="https://formulae.brew.sh")
T("brew.casks", "Casks", B, "f59e0b", [d("/opt/homebrew/Caskroom")],
  icon="homebrew", symbol="shippingbox.fill", website="https://formulae.brew.sh/cask")
T("brew.cache", "Download cache", B, "a16207", [d("~/Library/Caches/Homebrew")],
  icon="homebrew", symbol="internaldrive.fill")
T("brew.taps", "Taps", B, "d97706", [d("/opt/homebrew/Library/Taps")],
  icon="homebrew", symbol="spigot.fill")

# --------------------------------------------------------------------- Dev kits & SDKs
S = "sdk"
T("sdk.xcode", "Xcode", S, "1575f9", [app("/Applications/Xcode.app", "/Applications/Xcode-beta.app")],
  icon="xcode", symbol="hammer.fill", website="https://developer.apple.com/xcode")
T("sdk.clt", "Command Line Tools", S, "3b82f6", [d("/Library/Developer/CommandLineTools")],
  symbol="wrench.and.screwdriver.fill", website="https://developer.apple.com/xcode/resources")
T("sdk.xcodedata", "Xcode support data", S, "60a5fa", [d("~/Library/Developer/Xcode")],
  icon="xcode", symbol="folder.fill")
T("sdk.coresimulator", "CoreSimulator", S, "22d3ee", [d("~/Library/Developer/CoreSimulator")],
  symbol="iphone.gen3")
T("sdk.coredevice", "CoreDevice", S, "38bdf8", [d("/Library/Developer/CoreDevice")],
  symbol="cable.connector")
T("sdk.ddi", "DeveloperDiskImages", S, "0ea5e9", [d("/Library/Developer/DeveloperDiskImages")],
  symbol="externaldrive.fill")
T("sdk.toolchains", "Swift toolchains", S, "f05138", [vm("xcodeToolchains")],
  icon="swift", symbol="swift")
T("sdk.jdk", "JDK", S, "e76f00", [vm("jvm")],
  icon="openjdk", symbol="cup.and.saucer.fill", website="https://openjdk.org")
T("sdk.android", "Android SDK", S, "3ddc84", [d("~/Library/Android/sdk")],
  icon="android", symbol="candybarphone", website="https://developer.android.com",
  missing="no platform-tools")
T("sdk.flutter", "Flutter SDK", S, "02569b", [d("~/development/flutter"), d("~/flutter"), d("/opt/homebrew/Caskroom/flutter")],
  icon="flutter", symbol="bird.fill", website="https://flutter.dev", missing="no SDK")
T("sdk.reactnative", "React Native CLI", S, "61dafb", [exe("react-native")],
  icon="react", symbol="atom", website="https://reactnative.dev", missing="not present")
T("sdk.unity", "Unity", S, "222c37", [d("/Applications/Unity"), app("/Applications/Unity Hub.app")],
  icon="unity", symbol="cube.transparent.fill", website="https://unity.com", missing="no editor")
T("sdk.godot", "Godot", S, "478cbf", [app("/Applications/Godot.app")],
  icon="godotengine", symbol="gamecontroller.fill", website="https://godotengine.org", missing="not present")
T("sdk.aws", "AWS CLI", S, "ff9900", [d("/usr/local/aws-cli"), formula("awscli"), exe("aws")],
  symbol="cloud.fill", website="https://aws.amazon.com/cli", missing="not present")
T("sdk.gcloud", "Google Cloud SDK", S, "4285f4", [d("~/google-cloud-sdk"), d("/opt/homebrew/Caskroom/google-cloud-sdk"), exe("gcloud")],
  icon="googlecloud", symbol="cloud.fill", website="https://cloud.google.com/sdk", missing="not present")
T("sdk.azure", "Azure CLI", S, "0078d4", [formula("azure-cli"), exe("az")],
  symbol="cloud.fill", website="https://learn.microsoft.com/cli/azure", missing="not present")
T("sdk.firebase", "Firebase CLI", S, "ffca28", [formula("firebase-cli"), exe("firebase")],
  icon="firebase", symbol="flame.fill", website="https://firebase.google.com/docs/cli", missing="not present")
T("sdk.kubectl", "kubectl", S, "326ce5", [formula("kubernetes-cli"), exe("kubectl")],
  icon="kubernetes", symbol="helm", website="https://kubernetes.io", missing="not present")
T("sdk.terraform", "Terraform", S, "7b42bc", [formula("terraform"), exe("terraform")],
  icon="terraform", symbol="square.grid.3x3.fill", website="https://terraform.io", missing="not present")
T("sdk.ansible", "Ansible", S, "ee0000", [formula("ansible"), exe("ansible")],
  icon="ansible", symbol="a.square.fill", website="https://ansible.com", missing="not present")
T("sdk.vagrant", "Vagrant", S, "1868f2", [cask("vagrant"), exe("vagrant")],
  icon="vagrant", symbol="shippingbox.fill", website="https://vagrantup.com", missing="not present")

# ------------------------------------------------------------------- IDEs & dev tools
I = "ide"
T("ide.xcodeapp", "Xcode", I, "1575f9", [app("/Applications/Xcode.app")],
  icon="xcode", symbol="hammer.fill", website="https://developer.apple.com/xcode")
T("ide.vscode", "VS Code", I, "0098ff", [app("/Applications/Visual Studio Code.app")],
  symbol="chevron.left.forwardslash.chevron.right", website="https://code.visualstudio.com")
T("ide.vscodeext", "VS Code extensions", I, "38bdf8", [d("~/.vscode/extensions")],
  symbol="puzzlepiece.extension.fill")
T("ide.cursor", "Cursor", I, "111827", [app("/Applications/Cursor.app")],
  symbol="cursorarrow.rays", website="https://cursor.com")
T("ide.cursordata", "Cursor data", I, "374151", [d("~/.cursor")],
  symbol="externaldrive.fill")
T("ide.zed", "Zed", I, "084ccf", [app("/Applications/Zed.app")],
  icon="zedindustries", symbol="bolt.square.fill", website="https://zed.dev", missing="not present")
T("ide.intellij", "IntelliJ IDEA", I, "000000", [app("/Applications/IntelliJ IDEA.app", "/Applications/IntelliJ IDEA CE.app")],
  icon="intellijidea", symbol="lightbulb.fill", website="https://jetbrains.com/idea", missing="not present")
T("ide.pycharm", "PyCharm", I, "21d789", [app("/Applications/PyCharm.app", "/Applications/PyCharm CE.app")],
  icon="pycharm", symbol="p.square.fill", website="https://jetbrains.com/pycharm", missing="not present")
T("ide.webstorm", "WebStorm", I, "07c3f2", [app("/Applications/WebStorm.app")],
  icon="webstorm", symbol="globe", website="https://jetbrains.com/webstorm", missing="not present")
T("ide.goland", "GoLand", I, "00acc1", [app("/Applications/GoLand.app")],
  icon="goland", symbol="g.square.fill", website="https://jetbrains.com/go", missing="not present")
T("ide.androidstudio", "Android Studio", I, "3ddc84", [app("/Applications/Android Studio.app")],
  icon="androidstudio", symbol="candybarphone", website="https://developer.android.com/studio",
  missing="not present")
T("ide.sublime", "Sublime Text", I, "ff9800", [app("/Applications/Sublime Text.app")],
  icon="sublimetext", symbol="doc.text.fill", website="https://sublimetext.com")
T("ide.neovim", "Neovim", I, "57a143", [formula("neovim"), exe("nvim")],
  icon="neovim", symbol="n.square.fill", website="https://neovim.io")
T("ide.warp", "Warp", I, "01a0f7", [app("/Applications/Warp.app")],
  icon="warp", symbol="terminal.fill", website="https://warp.dev")
T("ide.iterm", "iTerm2", I, "000000", [app("/Applications/iTerm.app")],
  icon="iterm2", symbol="terminal.fill", website="https://iterm2.com", missing="not present")
T("ide.ghostty", "Ghostty", I, "1d1d1d", [app("/Applications/Ghostty.app")],
  symbol="terminal.fill", website="https://ghostty.org", missing="not present")
T("ide.postman", "Postman", I, "ff6c37", [app("/Applications/Postman.app")],
  icon="postman", symbol="paperplane.fill", website="https://postman.com", missing="not present")
T("ide.insomnia", "Insomnia", I, "4000bf", [app("/Applications/Insomnia.app")],
  icon="insomnia", symbol="moon.zzz.fill", website="https://insomnia.rest", missing="not present")
T("ide.tableplus", "TablePlus", I, "3f7dd8", [app("/Applications/TablePlus.app")],
  symbol="tablecells.fill", website="https://tableplus.com", missing="not present")
T("ide.docker", "Docker Desktop", I, "2496ed", [app("/Applications/Docker.app")],
  icon="docker", symbol="shippingbox.fill", website="https://docker.com", missing="no container runtime")
T("ide.orbstack", "OrbStack", I, "f24e1e", [app("/Applications/OrbStack.app")],
  symbol="circle.hexagongrid.fill", website="https://orbstack.dev", missing="not present")
T("ide.podman", "Podman", I, "892ca0", [app("/Applications/Podman Desktop.app"), formula("podman"), exe("podman")],
  icon="podman", symbol="pawprint.fill", website="https://podman.io", missing="not present")
T("ide.colima", "Colima", I, "0f9d58", [formula("colima"), exe("colima")],
  symbol="cloud.fill", website="https://github.com/abiosoft/colima", missing="not present")
T("ide.figma", "Figma", I, "f24e1e", [app("/Applications/Figma.app")],
  icon="figma", symbol="paintbrush.pointed.fill", website="https://figma.com", missing="not present")

# ------------------------------------------------------------------- Shell & core
H = "shell"
T("shell.zsh", "zsh", H, "4b5563", [exe("zsh")],
  symbol="terminal.fill", website="https://zsh.org")
T("shell.bash", "bash", H, "4eaa25", [formula("bash"), exe("bash")],
  icon="gnubash", symbol="terminal.fill", website="https://gnu.org/software/bash")
T("shell.fish", "fish", H, "4aae47", [formula("fish"), exe("fish")],
  icon="fishshell", symbol="fish.fill", website="https://fishshell.com", missing="not present")
T("shell.nushell", "Nushell", H, "4e9a06", [formula("nushell"), exe("nu")],
  symbol="terminal.fill", website="https://nushell.sh", missing="not present")
T("shell.omz", "oh-my-zsh", H, "8b5cf6", [d("~/.oh-my-zsh")],
  symbol="sparkles", website="https://ohmyz.sh", missing="not present")
T("shell.starship", "Starship", H, "dd0b78", [formula("starship"), exe("starship")],
  icon="starship", symbol="star.fill", website="https://starship.rs", missing="not present")
T("shell.p10k", "powerlevel10k", H, "1e88e5", [d("~/.oh-my-zsh/custom/themes/powerlevel10k"), d("/opt/homebrew/share/powerlevel10k")],
  symbol="chevron.right.2", website="https://github.com/romkatv/powerlevel10k", missing="not present")
T("shell.git", "git", H, "f05033", [d("/Library/Developer/CommandLineTools/usr/bin/git"), formula("git"), exe("git")],
  icon="git", symbol="arrow.triangle.branch", website="https://git-scm.com")
T("shell.gh", "GitHub CLI", H, "181717", [formula("gh"), exe("gh")],
  icon="github", symbol="terminal.fill", website="https://cli.github.com", missing="not present")
T("shell.gitlfs", "Git LFS", H, "f64935", [formula("git-lfs"), exe("git-lfs")],
  icon="gitlfs", symbol="arrow.down.doc.fill", website="https://git-lfs.com", missing="not present")
T("shell.lazygit", "lazygit", H, "308000", [formula("lazygit"), exe("lazygit")],
  symbol="arrow.triangle.pull", website="https://github.com/jesseduffield/lazygit", missing="not present")
T("shell.tmux", "tmux", H, "1bb91f", [formula("tmux"), exe("tmux")],
  icon="tmux", symbol="rectangle.split.3x1.fill", website="https://github.com/tmux/tmux", missing="not present")
T("shell.ripgrep", "ripgrep", H, "b8312f", [formula("ripgrep"), exe("rg")],
  symbol="magnifyingglass", website="https://github.com/BurntSushi/ripgrep", missing="not present")
T("shell.fd", "fd", H, "6d28d9", [formula("fd"), exe("fd")],
  symbol="doc.text.magnifyingglass", website="https://github.com/sharkdp/fd", missing="not present")
T("shell.fzf", "fzf", H, "4a90d9", [formula("fzf"), exe("fzf")],
  symbol="line.3.horizontal.decrease.circle.fill", website="https://github.com/junegunn/fzf", missing="not present")
T("shell.jq", "jq", H, "2f6e9e", [formula("jq"), exe("jq")],
  symbol="curlybraces.square.fill", website="https://jqlang.github.io/jq", missing="not present")
T("shell.curl", "curl", H, "073551", [exe("curl")],
  icon="curl", symbol="arrow.down.circle.fill", website="https://curl.se")
T("shell.wget", "wget", H, "5a5a5a", [formula("wget"), exe("wget")],
  symbol="arrow.down.to.line", website="https://gnu.org/software/wget", missing="not present")
T("shell.rosetta", "Rosetta 2", H, "8e8e93", [d("/Library/Apple/usr/share/rosetta", "x86_64 translation")],
  symbol="cpu.fill", missing="not installed")
T("shell.sqlite", "SQLite", H, "003b57", [exe("sqlite3")],
  icon="sqlite", symbol="cylinder.fill", website="https://sqlite.org")
T("shell.postgres", "PostgreSQL", H, "4169e1", [formula("postgresql@17"), formula("postgresql@16"), app("/Applications/Postgres.app"), exe("psql")],
  icon="postgresql", symbol="cylinder.split.1x2.fill", website="https://postgresql.org", missing="not present")
T("shell.mysql", "MySQL", H, "4479a1", [formula("mysql"), exe("mysql")],
  icon="mysql", symbol="cylinder.fill", website="https://mysql.com", missing="not present")
T("shell.mongodb", "MongoDB", H, "47a248", [formula("mongodb-community"), exe("mongod")],
  icon="mongodb", symbol="leaf.fill", website="https://mongodb.com", missing="not present")
T("shell.redis", "Redis", H, "ff4438", [formula("redis"), exe("redis-server")],
  icon="redis", symbol="bolt.horizontal.fill", website="https://redis.io", missing="not present")

ids = [t["id"] for t in tools]
assert len(ids) == len(set(ids)), "duplicate ids: %s" % [i for i in ids if ids.count(i) > 1]

out = os.path.join(os.path.dirname(__file__), "..", "Sources", "DevShop", "Catalog", "catalog.json")
with open(out, "w") as f:
    json.dump(tools, f, indent=1)
    f.write("\n")
print("%d tools -> %s" % (len(tools), os.path.relpath(out)), file=sys.stderr)
