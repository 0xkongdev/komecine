import Foundation
import Combine
import SwiftUI
import Security
import GoogleSignIn

struct AuthConfiguration {
    let googleClientID: String
    let googleServerClientID: String
    let backendURL: URL
    init?(values: [String: Any]) {
        guard let client = values["GoogleClientID"] as? String, !client.isEmpty,
              let server = values["GoogleServerClientID"] as? String, !server.isEmpty,
              let address = values["BackendURL"] as? String, let url = URL(string: address),
              url.scheme == "https", url.host != nil else { return nil }
        googleClientID = client; googleServerClientID = server; backendURL = url
    }
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "KomeCineConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return Self(values: values)
    }
}

@MainActor final class AuthManager: ObservableObject {
    @Published private(set) var userID: String? = UserDefaults.standard.string(forKey:"auth.userID")
    @Published private(set) var displayName: String? = UserDefaults.standard.string(forKey:"auth.displayName")
    @Published var message: String?
    @Published var busy = false
    let configuration = AuthConfiguration.load()
    var token: String? { Keychain.read() }
    func signIn() async {
        guard let config=configuration else { message="Chưa cấu hình Google và máy chủ KomeCine."; return }
        guard let window=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).flatMap(\.windows).first(where:{$0.isKeyWindow}), let presenter=window.rootViewController else { message="Không thể mở màn hình đăng nhập."; return }
        busy=true; defer { busy=false }
        do {
            GIDSignIn.sharedInstance.configuration=GIDConfiguration(clientID:config.googleClientID,serverClientID:config.googleServerClientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting:presenter)
            guard let idToken=result.user.idToken?.tokenString else { throw APIError.invalidResponse }
            let url=config.backendURL.appending(path:"/api/auth/sign-in/social")
            var request=URLRequest(url:url); request.httpMethod="POST"; request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:["provider":"google","idToken":["token":idToken,"accessToken":result.user.accessToken.tokenString]])
            let (data,response)=try await URLSession.shared.data(for:request)
            guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let token=http.value(forHTTPHeaderField:"set-auth-token"),
                  let root=try JSONSerialization.jsonObject(with:data) as? [String:Any], let user=root["user"] as? [String:Any], let id=user["id"] as? String else { throw APIError.invalidResponse }
            guard Keychain.write(token) else { throw APIError.invalidResponse }
            userID=id; displayName=user["name"] as? String
            UserDefaults.standard.set(id,forKey:"auth.userID"); UserDefaults.standard.set(displayName,forKey:"auth.displayName"); message=nil
        } catch { message="Không thể đăng nhập. Vui lòng kiểm tra cấu hình và thử lại." }
    }
    func signOut() async {
        if let config=configuration, let token {
            var request=URLRequest(url:config.backendURL.appending(path:"/api/auth/sign-out")); request.httpMethod="POST"; request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
            _ = try? await URLSession.shared.data(for:request)
        }
        GIDSignIn.sharedInstance.signOut(); Keychain.clear(); userID=nil; displayName=nil
        UserDefaults.standard.removeObject(forKey:"auth.userID"); UserDefaults.standard.removeObject(forKey:"auth.displayName")
    }
}
private enum Keychain {
    private static let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.komecine.session",kSecAttrAccount as String:"token"]
    static func read()->String? { var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne; var result:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess, let data=result as? Data else{return nil}; return String(data:data,encoding:.utf8) }
    static func write(_ token:String)->Bool { clear(); var q=query; q[kSecValueData as String]=Data(token.utf8); q[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; return SecItemAdd(q as CFDictionary,nil)==errSecSuccess }
    static func clear(){ SecItemDelete(query as CFDictionary) }
}
