import SwiftUI

struct AlbumView: View {
    let images: [SpotImage]
    let title: String

    @State private var selectedURL: String?
    @State private var showPreview = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Button {
                        selectedURL = image.image_url
                        showPreview = true
                    } label: {
                        AsyncImage(url: URL(string: image.image_url ?? "")) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.gray.opacity(0.12)
                            }
                        }
                        .frame(minHeight: 110)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPreview) {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: selectedURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .onTapGesture { showPreview = false }
            }
        }
    }
}
