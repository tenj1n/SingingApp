import SwiftUI

@main
struct SingingTrainerApp: App {
    @StateObject private var userSession = UserSession()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(userSession)
        }
    }
}
