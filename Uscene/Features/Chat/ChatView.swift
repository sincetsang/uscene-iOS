import SwiftUI

struct ChatView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let conversationId: String?
    let title: String
    var initialMessage: String = ""

    @State private var activeConversationId: String?
    @State private var messages: [DisplayMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    struct DisplayMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isUser: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.isUser { Spacer(minLength: 40) }
                                Group {
                                    if message.isUser {
                                        Text(message.text)
                                    } else {
                                        Text(.init(message.text))
                                    }
                                }
                                .padding(10)
                                .background(message.isUser ? Theme.brand : Color(.secondarySystemBackground))
                                .foregroundStyle(message.isUser ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                if !message.isUser { Spacer(minLength: 40) }
                            }
                            .id(message.id)
                        }
                        if isSending {
                            HStack {
                                ProgressView()
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Spacer(minLength: 40)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }

            HStack(spacing: 10) {
                TextField(language.t("uai.placeholder"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await send(draft) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Theme.brand)
                }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if activeConversationId != nil {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(language.t("uai.deleteConversation"))
                }
            }
        }
        .confirmationDialog(language.t("uai.deleteConversation"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(language.t("common.delete"), role: .destructive) {
                Task { await deleteConversation() }
            }
            Button(language.t("common.cancel"), role: .cancel) {}
        }
        .task {
            activeConversationId = conversationId
            if let conversationId {
                await loadThread(id: conversationId)
            }
            if !initialMessage.isEmpty {
                draft = initialMessage
                await send(initialMessage)
            }
        }
    }

    @MainActor
    private func loadThread(id: String) async {
        do {
            let thread = try await ChatAPI.thread(id: id)
            messages = thread.map {
                DisplayMessage(text: $0.content ?? "", isUser: $0.isFromUser)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteConversation() async {
        guard let id = activeConversationId else { return }
        do {
            try await ChatAPI.deleteConversation(id: id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func send(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        messages.append(DisplayMessage(text: content, isUser: true))
        draft = ""
        do {
            let isNew = activeConversationId == nil
            let response = try await ChatAPI.send(
                content: content,
                conversationId: activeConversationId,
                isNew: isNew,
                city: ""
            )
            if let cid = response.conversation_id, !cid.isEmpty {
                activeConversationId = cid
            }
            if let reply = response.content, !reply.isEmpty {
                messages.append(DisplayMessage(text: reply, isUser: false))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
