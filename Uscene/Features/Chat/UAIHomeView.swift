import SwiftUI
import UIKit

struct UAIHomeView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var recommended: [ChatRecommended] = []
    @State private var conversations: [ChatConversation] = []
    @State private var showLogin = false
    @State private var showHistory = false
    @State private var errorMessage: String?
    @State private var navigateToNewChat = false
    @State private var pendingMessage = ""
    @State private var pendingTitle: String?

    private let quickTags = ["chat.travelSpecialist", "chat.graduationTrip", "chat.foodGuide"]

    var body: some View {
        ZStack {
            Theme.uaiWash.ignoresSafeArea()

            Image("AIBG")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 375, alignment: .top)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showHistory = true
                    } label: {
                        Image("HistoryChat")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 16)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .tabRootHeaderInset(12)

                Spacer().frame(height: 100)

                recommendedCard
                    .padding(.horizontal, 16)

                Spacer(minLength: 8)

                bottomInputBar
            }

            if showHistory {
                historyDrawer
                    .transition(.move(edge: .trailing))
                    .zIndex(20)
            }
        }
        .tabRootChrome()
        .animation(.easeInOut(duration: 0.25), value: showHistory)
        .navigationDestination(isPresented: $navigateToNewChat) {
            ChatView(
                conversationId: nil,
                title: pendingTitle ?? language.t("tabbar.uai"),
                initialMessage: pendingMessage
            )
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .task { await load() }
    }

    private var recommendedCard: some View {
        VStack(spacing: 14) {
            if recommended.isEmpty {
                Text(language.t("uai.recommended"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(recommended) { item in
                            Button {
                                startChat(message: item.title ?? "", title: item.title)
                            } label: {
                                HStack(spacing: 10) {
                                    Image("ManageAI")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text(item.title ?? "")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.text)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Image("MoreBlue")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .top)
        .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 1)
        )
    }

    private var bottomInputBar: some View {
        VStack(spacing: 8) {
            Button {
                startChat(message: "", title: nil)
            } label: {
                HStack {
                    Text(language.t("uai.placeholder"))
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                    Spacer()
                    Image("SendIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Theme.inputBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickTags, id: \.self) { key in
                        Button {
                            let title = language.t(key)
                            startChat(message: title, title: title)
                        } label: {
                            Text("# \(language.t(key))")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .overlay(Capsule().stroke(Theme.inputBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 40)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var historyDrawer: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showHistory = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language.t("uai.history"))
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button { showHistory = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.text)
                    }
                }
                .padding(16)

                Divider()

                if conversations.isEmpty {
                    Text(language.t("uai.noHistory"))
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(conversations) { item in
                            NavigationLink {
                                ChatView(conversationId: item.id, title: item.title ?? language.t("tabbar.uai"))
                            } label: {
                                Text(item.title ?? item.id)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await delete(id: item.id) }
                                } label: {
                                    Label(language.t("common.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: min(320, UIScreen.main.bounds.width * 0.82))
            .frame(maxHeight: .infinity)
            .background(Color.white)
        }
    }

    private func startChat(message: String, title: String?) {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        pendingMessage = message
        pendingTitle = title
        showHistory = false
        navigateToNewChat = true
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            recommended = try await ChatAPI.recommended()
            if auth.isLoggedIn {
                conversations = try await ChatAPI.conversations()
            } else {
                conversations = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(id: String) async {
        try? await ChatAPI.deleteConversation(id: id)
        conversations.removeAll { $0.id == id }
    }
}
