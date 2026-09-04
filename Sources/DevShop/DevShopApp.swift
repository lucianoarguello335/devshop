import SwiftUI

@main
struct DevShopApp: App {
    @State private var model = AppModel()

    init() {
        // A window is pointless for a diagnostic dump, so handle that before one opens.
        guard Diagnostics.isRequested else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await Diagnostics.run()
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    var body: some Scene {
        Window("DevShop", id: "main") {
            RootWindow(model: model)
                .task { await model.start() }
        }
        .defaultSize(width: 1180, height: 790)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isBusy)
                Button("Copy AI Prompt") { model.copyFindingsPrompt() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.findings.isEmpty)
            }
        }
    }
}
