import SwiftUI
import MapKit

struct AddressMapPickerView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    var onPick: (_ area: String, _ address: String, _ coordinate: CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var pin = CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723)
    @State private var resolvedArea = ""
    @State private var resolvedAddress = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                Marker(language.t("address.pin"), coordinate: pin)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                pin = context.region.center
                Task { await resolve() }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                if isResolving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    if !resolvedArea.isEmpty {
                        Text(resolvedArea)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(resolvedAddress.isEmpty ? language.t("address.mapHint") : resolvedAddress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    onPick(resolvedArea, resolvedAddress, pin)
                    dismiss()
                } label: {
                    Text(language.t("address.useLocation"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(resolvedAddress.isEmpty && resolvedArea.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(language.t("address.mapPick"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let coordinate = location.coordinate {
                        pin = coordinate
                        withAnimation {
                            position = .region(
                                MKCoordinateRegion(
                                    center: coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                                )
                            )
                        }
                        Task { await resolve() }
                    } else {
                        location.requestPermissionAndLocate()
                    }
                } label: {
                    Image(systemName: "location.fill")
                }
            }
        }
        .task {
            if let coordinate = location.coordinate {
                pin = coordinate
                position = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    )
                )
            }
            await resolve()
        }
    }

    @MainActor
    private func resolve() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        do {
            let payload = try await SpotAPI.reverseAddress(latitude: pin.latitude, longitude: pin.longitude)
            resolvedArea = payload.displayArea ?? ""
            resolvedAddress = payload.displayAddress ?? String(format: "%.5f, %.5f", pin.latitude, pin.longitude)
        } catch {
            // Fallback to Apple geocoder-ish coords text
            resolvedAddress = String(format: "%.5f, %.5f", pin.latitude, pin.longitude)
            errorMessage = error.localizedDescription
        }
    }
}
