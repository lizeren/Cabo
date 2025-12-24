import SwiftUI
import AVFoundation

@main
struct CaboGameApp: App {
    @StateObject private var audioManager = AudioManager.shared
    
    init() {
        // Configure audio session for background music
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
                .environmentObject(audioManager)
                .onAppear {
                    audioManager.playBackgroundMusic()
                }
        }
    }
}

