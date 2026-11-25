import SwiftUI

@main
struct LinedApp: App {
    @State private var environment = Result { try AppEnvironment() }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let environment):
                LibraryRootView()
                    .environment(environment)
                    .environment(environment.library)
            case .failure(let error):
                ContentUnavailableView(
                    "Lined can't open your library",
                    systemImage: "exclamationmark.triangle",
                    description: Text(ErrorMessage.text(for: error))
                )
            }
        }
    }
}
