import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct EnglishClozeCoachApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PracticeStore()

    var body: some Scene {
        WindowGroup("英语填空教练", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 940, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("上一题") {
                    store.goBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!store.canGoBack)

                Button("下一题") {
                    store.advance()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!store.canAdvance)

                Button("重置当前题") {
                    store.resetCurrentAnswers()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.selectedItem == nil)
            }
        }
    }
}
