import Foundation

// MARK: - Game Phase
enum GamePhase: String, Codable {
    case lobby              // Waiting for players
    case initialPeek        // Players peeking at 2 cards
    case playing            // Main game loop
    case reactionWindow     // 5-second reaction period
    case finalRound         // After Cabo called
    case scoring            // Revealing and scoring
    case gameOver           // Game ended
}

// MARK: - Turn Phase
enum TurnPhase: String, Codable {
    case drawing            // Player must draw
    case deciding           // Player deciding what to do with card
    case usingAbility       // Player using card ability
    case selectingTarget    // Player selecting target for ability
    case discarding         // Player discarding
    case waiting            // Not this player's turn
}

// MARK: - Draw Source
enum DrawSource: String, Codable {
    case deck
    case discardPile
}

// MARK: - Game State
struct GameState: Codable {
    // Room info
    var roomCode: String
    var hostPlayerId: UUID
    
    // Players
    var players: [Player]
    var currentPlayerIndex: Int
    var turnOrder: [UUID] // Player IDs in turn order
    
    // Game phase
    var phase: GamePhase
    var turnPhase: TurnPhase
    
    // Cards
    var deckCount: Int // Don't send actual deck to clients
    var discardPile: [Card]
    var drawnCard: Card? // Currently drawn card (only visible to drawing player)
    
    // Cabo state
    var caboCallerId: UUID?
    var playersWithFinalTurn: [UUID] // Changed from Set for JSON compatibility
    
    // Reaction window
    var reactionDeadline: String? // Changed from Date for JSON compatibility
    var pendingReactions: [String: Card] // Changed key type for JSON compatibility
    
    // Turn timer
    var turnDeadline: String? // Changed from Date for JSON compatibility
    var turnTimeLimit: TimeInterval
    
    // Round tracking
    var roundNumber: Int
    var gameScores: [String: Int] // Cumulative scores across rounds (String keys for JSON)
    
    init(roomCode: String, hostPlayerId: UUID) {
        self.roomCode = roomCode
        self.hostPlayerId = hostPlayerId
        self.players = []
        self.currentPlayerIndex = 0
        self.turnOrder = []
        self.phase = .lobby
        self.turnPhase = .waiting
        self.deckCount = 52
        self.discardPile = []
        self.drawnCard = nil
        self.caboCallerId = nil
        self.playersWithFinalTurn = []
        self.reactionDeadline = nil
        self.pendingReactions = [:]
        self.turnDeadline = nil
        self.turnTimeLimit = 60 // 60 seconds per turn
        self.roundNumber = 1
        self.gameScores = [:]
    }
    
    // MARK: - Computed Properties
    
    var currentPlayer: Player? {
        guard currentPlayerIndex >= 0 && currentPlayerIndex < turnOrder.count else {
            return nil
        }
        let playerId = turnOrder[currentPlayerIndex]
        return players.first { $0.id == playerId }
    }
    
    var currentPlayerId: UUID? {
        guard currentPlayerIndex >= 0 && currentPlayerIndex < turnOrder.count else {
            return nil
        }
        return turnOrder[currentPlayerIndex]
    }
    
    var topDiscard: Card? {
        discardPile.last
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return Self.isoFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    
    var isReactionWindowActive: Bool {
        guard let deadline = parseDate(reactionDeadline) else { return false }
        return Date() < deadline
    }
    
    var reactionTimeRemaining: TimeInterval {
        guard let deadline = parseDate(reactionDeadline) else { return 0 }
        return max(0, deadline.timeIntervalSinceNow)
    }
    
    var turnTimeRemaining: TimeInterval {
        guard let deadline = parseDate(turnDeadline) else { return turnTimeLimit }
        return max(0, deadline.timeIntervalSinceNow)
    }
    
    var activePlayers: [Player] {
        players.filter { $0.status == .playing }
    }
    
    var isCaboActive: Bool {
        caboCallerId != nil
    }
    
    // MARK: - Player Queries
    
    func player(withId id: UUID) -> Player? {
        players.first { $0.id == id }
    }
    
    func playerIndex(for id: UUID) -> Int? {
        players.firstIndex { $0.id == id }
    }
    
    mutating func updatePlayer(_ player: Player) {
        if let index = playerIndex(for: player.id) {
            players[index] = player
        }
    }
    
    // MARK: - Turn Management
    
    private static func formatDate(_ date: Date) -> String {
        return ISO8601DateFormatter().string(from: date)
    }
    
    mutating func advanceToNextPlayer() {
        guard !turnOrder.isEmpty else { return }
        
        var nextIndex = (currentPlayerIndex + 1) % turnOrder.count
        var attempts = 0
        
        // Skip disconnected players
        while attempts < turnOrder.count {
            let nextPlayerId = turnOrder[nextIndex]
            if let player = player(withId: nextPlayerId),
               player.status == .playing {
                break
            }
            nextIndex = (nextIndex + 1) % turnOrder.count
            attempts += 1
        }
        
        currentPlayerIndex = nextIndex
        turnPhase = .drawing
        turnDeadline = Self.formatDate(Date().addingTimeInterval(turnTimeLimit))
    }
    
    mutating func setCurrentPlayer(to playerId: UUID) {
        if let index = turnOrder.firstIndex(of: playerId) {
            currentPlayerIndex = index
            turnPhase = .drawing
            turnDeadline = Self.formatDate(Date().addingTimeInterval(turnTimeLimit))
        }
    }
    
    // MARK: - Reaction Window
    
    mutating func startReactionWindow() {
        phase = .reactionWindow
        reactionDeadline = Self.formatDate(Date().addingTimeInterval(5.0)) // 5 second window
        pendingReactions = [:]
    }
    
    mutating func endReactionWindow() {
        reactionDeadline = nil
        pendingReactions = [:]
        
        if caboCallerId != nil {
            phase = .finalRound
        } else {
            phase = .playing
        }
    }
    
    // MARK: - Cabo Logic
    
    mutating func callCabo(by playerId: UUID) {
        guard caboCallerId == nil else { return }
        caboCallerId = playerId
        phase = .finalRound
        playersWithFinalTurn = [playerId] // Caller doesn't get another turn
    }
    
    mutating func markFinalTurnTaken(by playerId: UUID) {
        if !playersWithFinalTurn.contains(playerId) {
            playersWithFinalTurn.append(playerId)
        }
    }
    
    var allFinalTurnsTaken: Bool {
        let activePlayerIds = activePlayers.map { $0.id }
        return activePlayerIds.allSatisfy { playersWithFinalTurn.contains($0) }
    }
}

// MARK: - Game Result
struct GameResult: Codable {
    let winnerId: UUID
    let winnerName: String
    let scores: [PlayerScore]
    let wasCaboSuccessful: Bool // Did cabo caller win?
    
    struct PlayerScore: Codable, Identifiable {
        let id: UUID
        let playerId: UUID
        let playerName: String
        let score: Int
        let cards: [Card]
        let calledCabo: Bool
    }
}

// MARK: - Sanitized State (for sending to clients)
extension GameState {
    /// Creates a sanitized version of the state for a specific player
    /// Hides other players' face-down cards and the deck contents
    func sanitized(for playerId: UUID) -> GameState {
        var state = self
        
        // Hide other players' face-down cards
        for i in 0..<state.players.count {
            if state.players[i].id != playerId {
                for j in 0..<state.players[i].cards.count {
                    if !state.players[i].cards[j].isFaceUp {
                        // Replace with placeholder card (client should show face-down)
                        state.players[i].cards[j].card = Card(suit: .spades, rank: .ace)
                    }
                }
            }
        }
        
        // Hide drawn card if not the current player
        if currentPlayerId != playerId {
            state.drawnCard = nil
        }
        
        return state
    }
}

