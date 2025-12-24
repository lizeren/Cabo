import Foundation
import UIKit

// MARK: - Player Status
enum PlayerStatus: String, Codable {
    case waiting        // In lobby, not ready
    case ready          // Ready to start
    case playing        // In active game
    case disconnected   // Lost connection
    case spectating     // Watching (future feature)
}

// MARK: - Player
struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var status: PlayerStatus
    var cards: [PlayerCard]
    var score: Int
    var isHost: Bool
    var hasCalledCabo: Bool
    var peeksRemaining: Int // For initial peek phase
    var readyToPlay: Bool? // For initial peek ready state
    var peekedPositions: [Int]? // Positions of cards player has seen
    
    init(id: UUID = UUID(), name: String, isHost: Bool = false) {
        self.id = id
        self.name = name
        self.status = .waiting
        self.cards = []
        self.score = 0
        self.isHost = isHost
        self.hasCalledCabo = false
        self.peeksRemaining = 2
        self.readyToPlay = false
        self.peekedPositions = []
    }
    
    // MARK: - Card Management
    
    mutating func setCards(_ newCards: [Card]) {
        cards = newCards.enumerated().map { index, card in
            PlayerCard(card: card, position: index)
        }
    }
    
    mutating func replaceCard(at position: Int, with newCard: Card) -> Card? {
        guard position >= 0 && position < cards.count else { return nil }
        let oldCard = cards[position].card
        cards[position] = PlayerCard(card: newCard, position: position)
        return oldCard
    }
    
    mutating func revealCard(at position: Int) {
        guard position >= 0 && position < cards.count else { return }
        cards[position].isFaceUp = true
    }
    
    mutating func hideCard(at position: Int) {
        guard position >= 0 && position < cards.count else { return }
        cards[position].isFaceUp = false
    }
    
    mutating func revealAllCards() {
        for i in 0..<cards.count {
            cards[i].isFaceUp = true
        }
    }
    
    func card(at position: Int) -> PlayerCard? {
        guard position >= 0 && position < cards.count else { return nil }
        return cards[position]
    }
    
    // MARK: - Scoring
    
    func calculateScore() -> Int {
        cards.reduce(0) { $0 + $1.card.rank.scoreValue }
    }
    
    mutating func updateScore() {
        score = calculateScore()
    }
    
    // MARK: - Equatable
    
    static func == (lhs: Player, rhs: Player) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Local Player Info (for network identification)
struct LocalPlayerInfo: Codable {
    let playerId: UUID
    let playerName: String
    let deviceId: String
    
    static func create(name: String) -> LocalPlayerInfo {
        LocalPlayerInfo(
            playerId: UUID(),
            playerName: name,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
    }
}

