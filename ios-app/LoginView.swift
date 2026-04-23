import SwiftUI

struct LoginView: View {
    @State private var selectedTab: AuthTab = .login
    @State private var email        = ""
    @State private var password     = ""
    @State private var confirmPass  = ""
    @State private var fullName     = ""
    @State private var isLoading    = false
    @State private var navigateToSearch = false
    @State private var glowPulse    = false
    @State private var focusedField: AuthFieldType?

    enum AuthTab   { case login, signup }
    enum AuthFieldType { case name, email, password, confirm }

    private var canProceed: Bool {
        switch selectedTab {
        case .login:
            return !email.isEmpty && !password.isEmpty
        case .signup:
            return !fullName.isEmpty && !email.isEmpty
                && !password.isEmpty && !confirmPass.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                glowBackground
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                        tabToggle
                        fieldsSection
                        ctaSection
                        socialSection
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onTapGesture { focusedField = nil }
        }
    }

    // ── Extracted subviews ────────────────────────────────────────────────────

    private var glowBackground: some View {
        GeometryReader { geo in
            ZStack {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.45), .clear],
                        center: .center, startRadius: 0, endRadius: 220
                    ))
                    .frame(width: 360, height: 360)
                    .offset(x: geo.size.width * 0.6 + (glowPulse ? 10 : -10),
                            y: geo.size.height * 0.1 + (glowPulse ? 8 : -8))
                    .blur(radius: 40)
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.55, green: 0.2, blue: 0.9).opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: 200
                    ))
                    .frame(width: 320, height: 320)
                    .offset(x: geo.size.width * 0.05 + (glowPulse ? -8 : 8),
                            y: geo.size.height * 0.65 + (glowPulse ? 12 : -12))
                    .blur(radius: 45)
            }
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: glowPulse)
        }
        .ignoresSafeArea()
        .onAppear { glowPulse = true }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            BrandLogoView(containerSize: CGSize(width: 120, height: 120))
                .frame(width: 72, height: 72)
            Text("RideShift")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(selectedTab == .login ? "Welcome back" : "Create your account")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 60)
        .padding(.bottom, 36)
    }

    private var tabToggle: some View {
        HStack(spacing: 0) {
            tabButton(.login,  label: "Log In")
            tabButton(.signup, label: "Sign Up")
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    private func tabButton(_ tab: AuthTab, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedTab == tab ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedTab == tab ? Capsule().fill(Color.white) : nil)
        }
        .buttonStyle(.plain)
    }

    private var fieldsSection: some View {
        VStack(spacing: 14) {
            if selectedTab == .signup {
                AuthField(icon: "person.fill", placeholder: "Full name",
                          text: $fullName, field: .name,
                          focusedField: $focusedField, isSecure: false)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)))
            }
            AuthField(icon: "envelope.fill", placeholder: "Email address",
                      text: $email, field: .email,
                      focusedField: $focusedField, isSecure: false,
                      keyboardType: .emailAddress)
            AuthField(icon: "lock.fill", placeholder: "Password",
                      text: $password, field: .password,
                      focusedField: $focusedField, isSecure: true)
            if selectedTab == .signup {
                AuthField(icon: "lock.fill", placeholder: "Confirm password",
                          text: $confirmPass, field: .confirm,
                          focusedField: $focusedField, isSecure: true)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)))
            }
            if selectedTab == .login {
                Button("Forgot password?") {}
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.35), value: selectedTab)
    }

    private var ctaSection: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: RideSearchSetupView(), isActive: $navigateToSearch) {
                EmptyView()
            }
            Button {
                guard canProceed else { return }
                isLoading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    isLoading = false
                    navigateToSearch = true
                }
            } label: {
                ctaLabel
            }
            .disabled(!canProceed || isLoading)
            .animation(.easeInOut(duration: 0.2), value: canProceed)
            .padding(.horizontal, 24)
            .padding(.top, 28)
        }
    }

    private var ctaLabel: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(.black)
            } else {
                Text(selectedTab == .login ? "Log In" : "Create Account")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .tracking(0.2)
                ZStack {
                    Circle().fill(Color.black.opacity(0.12)).frame(width: 28, height: 28)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
            }
        }
        .foregroundStyle(canProceed ? .black : .white.opacity(0.25))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(ctaBackground)
        .overlay(Capsule().stroke(Color.white.opacity(canProceed ? 0.2 : 0.06), lineWidth: 0.5))
    }

    private var ctaBackground: some View {
        Capsule().fill(
            canProceed
                ? LinearGradient(colors: [.white, Color(red: 0.92, green: 0.92, blue: 0.95)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.08)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var socialSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                Text("or continue with")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            HStack(spacing: 14) {
                SocialButton(label: "Apple",  icon: "apple.logo")  { navigateToSearch = true }
                SocialButton(label: "Google", icon: "g.circle.fill") { navigateToSearch = true }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }
}



// ── Auth input field ──────────────────────────────────────────────────────────

private struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let field: LoginView.AuthFieldType
    @Binding var focusedField: LoginView.AuthFieldType?
    let isSecure: Bool
    var keyboardType: UIKeyboardType = .default

    var isFocused: Bool { focusedField == field }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFocused ? Color(red: 0.4, green: 0.8, blue: 1.0) : .white.opacity(0.3))
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt:
                        Text(placeholder).foregroundColor(.white.opacity(0.25))
                    )
                } else {
                    TextField("", text: $text, prompt:
                        Text(placeholder).foregroundColor(.white.opacity(0.25))
                    )
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                }
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isFocused
                    ? Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.5)
                    : Color.white.opacity(0.08),
                    lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .onTapGesture { focusedField = field }
    }
}

// ── Social login button ───────────────────────────────────────────────────────

private struct SocialButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
