import SwiftUI

struct AuthView: View {
    private enum AuthMode: Hashable {
        case login
        case create
    }

    @ObservedObject var sessionStore: UserSessionStore
    @State private var mode: AuthMode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("whatever")
                    .font(.system(size: 44, weight: .semibold))

                Picker("账户", selection: $mode) {
                    Text("登录").tag(AuthMode.login)
                    Text("创建").tag(AuthMode.create)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            VStack(spacing: 14) {
                TextField("用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)

                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)

                if mode == .create {
                    SecureField("确认密码", text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }
            .onSubmit(submit)

            if let authError = sessionStore.authError {
                Text(authError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button {
                submit()
            } label: {
                Label(mode == .login ? "登录" : "创建用户", systemImage: mode == .login ? "person.crop.circle" : "person.crop.circle.badge.plus")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            if !sessionStore.hasAccounts {
                mode = .create
            }
        }
    }

    private func submit() {
        switch mode {
        case .login:
            _ = sessionStore.login(username: username, password: password)
        case .create:
            _ = sessionStore.createUser(
                username: username,
                password: password,
                confirmation: confirmation
            )
        }
    }
}
