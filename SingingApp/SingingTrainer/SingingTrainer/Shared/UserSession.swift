import Foundation
import SwiftUI

@MainActor
final class UserSession: ObservableObject {
    
    @Published var userId: String?
    @Published var isReady: Bool = false
    @Published var errorMessage: String?
    
    init(previewUserId: String? = nil) {
        if let previewUserId {
            self.userId = previewUserId
            self.isReady = true
        }
    }
    
    func bootstrapIfNeeded(displayName: String?) async {
        if isReady { return }
        
        // ① まずKeychainから復元（ここで取れれば userId 固定になる）
        if let saved = KeychainHelper.loadUserId(), !saved.isEmpty {
            self.userId = saved
            self.isReady = true
            self.errorMessage = nil
            return
        }
        
        // ② 無ければサーバで作って保存
        do {
            let uid = try await UserAPI.shared.createUser(displayName: displayName)
            
            // 保存（次回起動で復元できるように）
            KeychainHelper.saveUserId(uid)
            
            self.userId = uid
            self.isReady = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            self.isReady = false
        }
    }
    
    // デバッグ用：userId を作り直したい時に呼ぶ
    func resetUser() {
        KeychainHelper.deleteUserId()
        self.userId = nil
        self.isReady = false
        self.errorMessage = nil
    }
}
