import SwiftUI

struct MyCommentsView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var items: [MarketplaceOrderRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var commentingOrderId: Int?

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "star")
                } actions: {
                    Button(language.t("login.signIn")) { showLogin = true }
                }
            } else if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(language.t("comment.empty"), systemImage: "star.slash")
            } else {
                List(items) { row in
                    Button {
                        commentingOrderId = row.order?.order_id
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: row.product?.cover ?? row.order?.head_img ?? "")) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default: Color.gray.opacity(0.12)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.product?.name ?? row.order?.product_name ?? "Order")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(row.order?.displayAmount ?? "-")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                Text(language.t("comment.write"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("comment.title"))
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .sheet(isPresented: Binding(
            get: { commentingOrderId != nil },
            set: { if !$0 { commentingOrderId = nil } }
        )) {
            if let commentingOrderId {
                NavigationStack {
                    OrderCommentView(orderId: commentingOrderId, isEdit: false) {
                        self.commentingOrderId = nil
                        Task { await load() }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard auth.isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await CommerceAPI.bought(pendingComment: 1).items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct OrderCommentView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let orderId: Int
    var isEdit: Bool = false
    var onDone: () -> Void

    @State private var star = 5
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(language.t("comment.rating")) {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            star = value
                        } label: {
                            Image(systemName: value <= star ? "star.fill" : "star")
                                .foregroundStyle(.orange)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section(language.t("comment.content")) {
                TextField(language.t("comment.placeholder"), text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(isEdit ? language.t("comment.edit") : language.t("comment.write"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("common.done")) {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
            }
        }
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = language.t("comment.requireContent")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if isEdit {
                try await CommerceAPI.updateOrderComment(orderId: orderId, star: star, comment: text)
            } else {
                try await CommerceAPI.addOrderComment(orderId: orderId, star: star, comment: text)
            }
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
