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
    @StateObject private var sessionStore = UserSessionStore()
    @StateObject private var studyStore = StudyStore()

    var body: some Scene {
        WindowGroup("whatever", id: "main") {
            Group {
                if sessionStore.currentUser != nil {
                    ContentView(
                        store: store,
                        sessionStore: sessionStore,
                        studyStore: studyStore
                    )
                    .id(sessionStore.currentUser?.id)
                } else {
                    AuthView(sessionStore: sessionStore)
                }
            }
                .frame(minWidth: 940, minHeight: 620)
                .onAppear {
                    syncUserState()
                }
                .onChange(of: sessionStore.currentUser?.id) {
                    syncUserState()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("上一题") {
                    store.goBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(sessionStore.currentUser == nil || !store.canGoBack)

                Button("下一题") {
                    store.advance()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(sessionStore.currentUser == nil || !store.canAdvance)

                Button("重置当前题") {
                    store.resetCurrentAnswers()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(sessionStore.currentUser == nil || store.selectedItem == nil)
            }
        }
    }

    private func syncUserState() {
        store.clearAnswers()

        if let user = sessionStore.currentUser {
            studyStore.load(for: user)
        } else {
            studyStore.clear()
        }
    }
}
