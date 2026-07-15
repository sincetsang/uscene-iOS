import SwiftUI
import RiveRuntime

struct LandRewardRiveView: View {
    let amountText: String
    var onConfirm: () -> Void

    @Environment(LanguageManager.self) private var language
    @StateObject private var viewModel = RiveViewModel(
        webURL: AppConfig.landRewardRiveURL,
        stateMachineName: "State Machine 1"
    )

    var body: some View {
        VStack(spacing: 16) {
            viewModel.view()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(language.t("ads.rewardUnlocked"))
                .font(.headline)
            Text(amountText)
                .font(.title2.bold())
                .foregroundStyle(Color.accentColor)

            Button(language.t("common.done")) {
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}
