import AVFoundation
import SwiftUI

// MARK: - Audio Manager
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private var backgroundMusicPlayer: AVAudioPlayer?
    @Published var isMusicPlaying: Bool = false
    @Published var musicVolume: Float = 0.3 {
        didSet {
            backgroundMusicPlayer?.volume = musicVolume
        }
    }
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func playBackgroundMusic() {
        guard backgroundMusicPlayer == nil || !backgroundMusicPlayer!.isPlaying else { return }
        
        // Try to find the music file in the bundle
        if let url = Bundle.main.url(forResource: "kahoot", withExtension: "mp3") {
            do {
                backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
                backgroundMusicPlayer?.numberOfLoops = -1 // Loop forever
                backgroundMusicPlayer?.volume = musicVolume
                backgroundMusicPlayer?.prepareToPlay()
                backgroundMusicPlayer?.play()
                isMusicPlaying = true
                print("Background music started")
            } catch {
                print("Failed to play background music: \(error)")
            }
        } else {
            print("Background music file not found in bundle")
        }
    }
    
    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
        backgroundMusicPlayer = nil
        isMusicPlaying = false
    }
    
    func pauseBackgroundMusic() {
        backgroundMusicPlayer?.pause()
        isMusicPlaying = false
    }
    
    func resumeBackgroundMusic() {
        backgroundMusicPlayer?.play()
        isMusicPlaying = true
    }
    
    func toggleMusic() {
        if isMusicPlaying {
            pauseBackgroundMusic()
        } else {
            if backgroundMusicPlayer != nil {
                resumeBackgroundMusic()
            } else {
                playBackgroundMusic()
            }
        }
    }
}

