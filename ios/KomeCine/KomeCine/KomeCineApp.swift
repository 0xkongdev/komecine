//
//  KomeCineApp.swift
//  KomeCine
//
//  Created by Kong on 10/29/26.
//

import SwiftUI
import GoogleSignIn

@main
struct KomeCineApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView().onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
