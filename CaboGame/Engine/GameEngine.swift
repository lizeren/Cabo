import Foundation
import Combine

// MARK: - Game Engine
/// The authoritative game logic handler. Runs on server or locally for single-player.
final class GameEngine {
    
    // MARK: - Properties
    
    private(set) var state: GameState
    private var deck: Deck
    private var reactionTimer: Timer?
    private var turnTimer: Timer?
    
    // Event publishers for state changes
    let stateDidChange = PassthroughSubject<GameState, Never>()
    let actionResult = PassthroughSubject<(UUID, ActionResult), Never>()
    let gameDidEnd = PassthroughSubject<GameResult, Never>()
    
    // MARK: - Initialization
    
    init(roomCode: String, hostPlayerId: UUID) {
        self.state = GameState(roomCode: roomCode, hostPlayerId: hostPlayerId)
        self.deck = Deck()
    }
    
    // MARK: - Player Management
    
    func addPlayer(_ player: Player) -> Result<Void, GameError> {
        guard state.phase == .lobby else {
            return .failure(.gameAlreadyStarted)
        }
        guard state.players.count < 4 else {
            return .failure(.roomFull)
        }
        
        var newPlayer = player
        newPlayer.status = .waiting
        state.players.append(newPlayer)
        broadcastStateUpdate()
        return .success(())
    }
    
    func removePlayer(_ playerId: UUID) {
        state.players.removeAll { $0.id == playerId }
        state.turnOrder.removeAll { $0 == playerId }
        
        // If game is in progress and player was current, advance turn
        if state.phase == .playing || state.phase == .finalRound {
            if state.currentPlayerId == playerId {
                state.advanceToNextPlayer()
            }
            
            // Check if only one player remains
            if state.activePlayers.count < 2 {
                endGameEarly()
            }
        }
        
        broadcastStateUpdate()
    }
    
    func setPlayerReady(_ playerId: UUID, isReady: Bool) -> Result<Void, GameError> {
        guard var player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        guard state.phase == .lobby else {
            return .failure(.gameAlreadyStarted)
        }
        
        player.status = isReady ? .ready : .waiting
        state.updatePlayer(player)
        broadcastStateUpdate()
        return .success(())
    }
    
    // MARK: - Game Flow
    
    func startGame() -> Result<Void, GameError> {
        guard state.phase == .lobby else {
            return .failure(.gameAlreadyStarted)
        }
        guard state.players.count >= 2 else {
            return .failure(.notEnoughPlayers)
        }
        
        // Initialize deck
        deck.reset()
        deck.shuffle()
        
        // Deal 4 cards to each player
        for i in 0..<state.players.count {
            let cards = deck.drawMultiple(4)
            state.players[i].setCards(cards)
            state.players[i].status = .playing
            state.players[i].peeksRemaining = 2
        }
        
        // Set up turn order (randomized)
        state.turnOrder = state.players.map { $0.id }.shuffled()
        state.currentPlayerIndex = 0
        
        // Put one card in discard pile
        if let firstDiscard = deck.draw() {
            state.discardPile = [firstDiscard]
        }
        
        state.deckCount = deck.count
        state.phase = .initialPeek
        
        broadcastStateUpdate()
        return .success(())
    }
    
    // MARK: - Initial Peek Phase
    
    func peekInitialCard(playerId: UUID, position: Int) -> Result<Card, GameError> {
        guard state.phase == .initialPeek else {
            return .failure(.invalidAction)
        }
        guard var player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        guard player.peeksRemaining > 0 else {
            return .failure(.invalidAction)
        }
        guard position >= 0 && position < 4 else {
            return .failure(.invalidCardPosition)
        }
        guard let playerCard = player.card(at: position) else {
            return .failure(.invalidCardPosition)
        }
        
        player.peeksRemaining -= 1
        state.updatePlayer(player)
        
        // Don't reveal to others, just return the card to this player
        return .success(playerCard.card)
    }
    
    func finishInitialPeek(playerId: UUID) -> Result<Void, GameError> {
        guard state.phase == .initialPeek else {
            return .failure(.invalidAction)
        }
        guard var player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        
        player.peeksRemaining = 0
        state.updatePlayer(player)
        
        // Check if all players have finished peeking
        let allDone = state.players.allSatisfy { $0.peeksRemaining == 0 }
        if allDone {
            state.phase = .playing
            state.turnPhase = .drawing
            state.turnDeadline = ISO8601DateFormatter().string(from: Date().addingTimeInterval(state.turnTimeLimit))
            startTurnTimer()
        }
        
        broadcastStateUpdate()
        return .success(())
    }
    
    // MARK: - Turn Actions
    
    func drawCard(playerId: UUID, from source: DrawSource) -> Result<Card, GameError> {
        guard state.phase == .playing || state.phase == .finalRound else {
            return .failure(.gameNotStarted)
        }
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .drawing else {
            return .failure(.invalidAction)
        }
        
        let drawnCard: Card?
        
        switch source {
        case .deck:
            drawnCard = deck.draw()
            state.deckCount = deck.count
        case .discardPile:
            guard !state.discardPile.isEmpty else {
                return .failure(.invalidAction)
            }
            drawnCard = state.discardPile.removeLast()
        }
        
        guard let card = drawnCard else {
            // Deck is empty, reshuffle discard pile
            reshuffleDiscardIntoDeck()
            if let reshuffledCard = deck.draw() {
                state.drawnCard = reshuffledCard
                state.deckCount = deck.count
                state.turnPhase = .deciding
                broadcastStateUpdate()
                return .success(reshuffledCard)
            }
            return .failure(.invalidAction)
        }
        
        state.drawnCard = card
        state.turnPhase = .deciding
        broadcastStateUpdate()
        return .success(card)
    }
    
    func replaceCard(playerId: UUID, at position: Int) -> Result<Card, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .deciding else {
            return .failure(.invalidAction)
        }
        guard let drawnCard = state.drawnCard else {
            return .failure(.noCardDrawn)
        }
        guard var player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        guard position >= 0 && position < 4 else {
            return .failure(.invalidCardPosition)
        }
        
        // Replace the card
        guard let discardedCard = player.replaceCard(at: position, with: drawnCard) else {
            return .failure(.invalidCardPosition)
        }
        
        state.updatePlayer(player)
        state.discardPile.append(discardedCard)
        state.drawnCard = nil
        
        // Start reaction window
        startReactionWindow(for: discardedCard)
        
        return .success(discardedCard)
    }
    
    func discardDrawnCard(playerId: UUID) -> Result<Void, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .deciding else {
            return .failure(.invalidAction)
        }
        guard let drawnCard = state.drawnCard else {
            return .failure(.noCardDrawn)
        }
        
        state.discardPile.append(drawnCard)
        state.drawnCard = nil
        
        // Check if card has ability
        if drawnCard.ability != .none {
            state.turnPhase = .usingAbility
            broadcastStateUpdate()
            return .success(())
        }
        
        // Start reaction window
        startReactionWindow(for: drawnCard)
        return .success(())
    }
    
    func useAbility(playerId: UUID) -> Result<Void, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .usingAbility else {
            return .failure(.invalidAction)
        }
        guard let discardedCard = state.topDiscard else {
            return .failure(.invalidAction)
        }
        guard discardedCard.ability != .none else {
            return .failure(.abilityNotAvailable)
        }
        
        state.turnPhase = .selectingTarget
        broadcastStateUpdate()
        return .success(())
    }
    
    func skipAbility(playerId: UUID) -> Result<Void, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .usingAbility else {
            return .failure(.invalidAction)
        }
        
        // Start reaction window with top discard
        if let topCard = state.topDiscard {
            startReactionWindow(for: topCard)
        } else {
            advanceToNextTurn()
        }
        return .success(())
    }
    
    // MARK: - Card Abilities
    
    func peekOwnCard(playerId: UUID, position: Int) -> Result<Card, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .selectingTarget else {
            return .failure(.invalidAction)
        }
        guard let topCard = state.topDiscard,
              topCard.ability == .peekOwn else {
            return .failure(.abilityNotAvailable)
        }
        guard let player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        guard position >= 0 && position < 4,
              let playerCard = player.card(at: position) else {
            return .failure(.invalidCardPosition)
        }
        
        // End turn after peeking
        startReactionWindow(for: topCard)
        
        return .success(playerCard.card)
    }
    
    func peekOpponentCard(playerId: UUID, targetPlayerId: UUID, position: Int) -> Result<Card, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .selectingTarget else {
            return .failure(.invalidAction)
        }
        guard let topCard = state.topDiscard,
              topCard.ability == .peekOther else {
            return .failure(.abilityNotAvailable)
        }
        guard playerId != targetPlayerId else {
            return .failure(.invalidPlayer)
        }
        guard let targetPlayer = state.player(withId: targetPlayerId) else {
            return .failure(.invalidPlayer)
        }
        guard position >= 0 && position < 4,
              let playerCard = targetPlayer.card(at: position) else {
            return .failure(.invalidCardPosition)
        }
        
        // End turn after peeking
        startReactionWindow(for: topCard)
        
        return .success(playerCard.card)
    }
    
    func swapCards(
        playerId: UUID,
        myPosition: Int,
        opponentId: UUID,
        opponentPosition: Int
    ) -> Result<Void, GameError> {
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .selectingTarget else {
            return .failure(.invalidAction)
        }
        guard let topCard = state.topDiscard,
              topCard.ability == .swap else {
            return .failure(.abilityNotAvailable)
        }
        guard playerId != opponentId else {
            return .failure(.invalidPlayer)
        }
        guard var myPlayer = state.player(withId: playerId),
              var opponent = state.player(withId: opponentId) else {
            return .failure(.invalidPlayer)
        }
        guard myPosition >= 0 && myPosition < 4,
              opponentPosition >= 0 && opponentPosition < 4 else {
            return .failure(.invalidCardPosition)
        }
        
        // Swap the cards
        let myCard = myPlayer.cards[myPosition].card
        let opponentCard = opponent.cards[opponentPosition].card
        
        myPlayer.cards[myPosition].card = opponentCard
        opponent.cards[opponentPosition].card = myCard
        
        state.updatePlayer(myPlayer)
        state.updatePlayer(opponent)
        
        // End turn after swapping
        startReactionWindow(for: topCard)
        
        return .success(())
    }
    
    // MARK: - Reaction System
    
    private func startReactionWindow(for card: Card) {
        state.startReactionWindow()
        broadcastStateUpdate()
        
        // Set up timer
        reactionTimer?.invalidate()
        reactionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.endReactionWindow()
        }
    }
    
    func reactWithCard(playerId: UUID, position: Int) -> Result<Void, GameError> {
        guard state.phase == .reactionWindow else {
            return .failure(.reactionWindowClosed)
        }
        guard state.isReactionWindowActive else {
            return .failure(.reactionWindowClosed)
        }
        guard playerId != state.currentPlayerId else {
            // Current player can't react to their own play
            return .failure(.invalidAction)
        }
        guard var player = state.player(withId: playerId) else {
            return .failure(.invalidPlayer)
        }
        guard position >= 0 && position < 4,
              let playerCard = player.card(at: position) else {
            return .failure(.invalidCardPosition)
        }
        guard let topDiscard = state.topDiscard else {
            return .failure(.invalidAction)
        }
        
        // Check if card matches
        guard playerCard.card.rank == topDiscard.rank else {
            return .failure(.cardDoesNotMatch)
        }
        
        // Accept reaction - first valid wins
        reactionTimer?.invalidate()
        
        // Remove card from player's hand and add to discard
        let reactedCard = player.cards[position].card
        player.cards.remove(at: position)
        
        // Reindex remaining cards
        for i in 0..<player.cards.count {
            player.cards[i].position = i
        }
        
        state.updatePlayer(player)
        state.discardPile.append(reactedCard)
        
        // Reacting player gets next turn
        state.endReactionWindow()
        state.setCurrentPlayer(to: playerId)
        
        broadcastStateUpdate()
        actionResult.send((playerId, .reactionAccepted(playerId: playerId)))
        
        return .success(())
    }
    
    private func endReactionWindow() {
        reactionTimer?.invalidate()
        reactionTimer = nil
        
        state.endReactionWindow()
        advanceToNextTurn()
    }
    
    // MARK: - Cabo
    
    func callCabo(playerId: UUID) -> Result<Void, GameError> {
        guard state.phase == .playing else {
            return .failure(.cannotCallCaboNow)
        }
        guard state.currentPlayerId == playerId else {
            return .failure(.notYourTurn)
        }
        guard state.turnPhase == .drawing else {
            // Can only call Cabo at start of turn before drawing
            return .failure(.cannotCallCaboNow)
        }
        guard state.caboCallerId == nil else {
            return .failure(.alreadyCalledCabo)
        }
        
        state.callCabo(by: playerId)
        
        // Move to next player for final round
        state.advanceToNextPlayer()
        
        broadcastStateUpdate()
        return .success(())
    }
    
    // MARK: - Turn Management
    
    private func advanceToNextTurn() {
        turnTimer?.invalidate()
        
        // Check if game should end
        if state.phase == .finalRound {
            state.markFinalTurnTaken(by: state.currentPlayerId!)
            
            if state.allFinalTurnsTaken {
                endGame()
                return
            }
        }
        
        // Check if deck is empty
        if deck.isEmpty && state.discardPile.count > 1 {
            reshuffleDiscardIntoDeck()
        }
        
        state.advanceToNextPlayer()
        startTurnTimer()
        broadcastStateUpdate()
    }
    
    private func startTurnTimer() {
        turnTimer?.invalidate()
        turnTimer = Timer.scheduledTimer(
            withTimeInterval: state.turnTimeLimit,
            repeats: false
        ) { [weak self] _ in
            self?.handleTurnTimeout()
        }
    }
    
    private func handleTurnTimeout() {
        // Auto-pass if player times out
        advanceToNextTurn()
    }
    
    private func reshuffleDiscardIntoDeck() {
        guard state.discardPile.count > 1 else { return }
        
        // Keep top card
        let topCard = state.discardPile.removeLast()
        
        // Shuffle rest into deck
        deck.setCards(state.discardPile)
        deck.shuffle()
        state.deckCount = deck.count
        
        // Reset discard pile with just top card
        state.discardPile = [topCard]
    }
    
    // MARK: - Game End
    
    private func endGame() {
        state.phase = .scoring
        
        // Reveal all cards
        for i in 0..<state.players.count {
            state.players[i].revealAllCards()
            state.players[i].updateScore()
        }
        
        // Calculate winner
        let sortedPlayers = state.players.sorted { $0.score < $1.score }
        guard let winner = sortedPlayers.first else { return }
        
        let wasCaboSuccessful = state.caboCallerId == winner.id
        
        let result = GameResult(
            winnerId: winner.id,
            winnerName: winner.name,
            scores: state.players.map { player in
                GameResult.PlayerScore(
                    id: UUID(),
                    playerId: player.id,
                    playerName: player.name,
                    score: player.score,
                    cards: player.cards.map { $0.card },
                    calledCabo: player.id == state.caboCallerId
                )
            },
            wasCaboSuccessful: wasCaboSuccessful
        )
        
        state.phase = .gameOver
        broadcastStateUpdate()
        gameDidEnd.send(result)
    }
    
    private func endGameEarly() {
        guard let winner = state.activePlayers.first else { return }
        
        let result = GameResult(
            winnerId: winner.id,
            winnerName: winner.name,
            scores: [
                GameResult.PlayerScore(
                    id: UUID(),
                    playerId: winner.id,
                    playerName: winner.name,
                    score: 0,
                    cards: [],
                    calledCabo: false
                )
            ],
            wasCaboSuccessful: false
        )
        
        state.phase = .gameOver
        broadcastStateUpdate()
        gameDidEnd.send(result)
    }
    
    // MARK: - State Broadcasting
    
    private func broadcastStateUpdate() {
        stateDidChange.send(state)
    }
    
    /// Get sanitized state for a specific player
    func getState(for playerId: UUID) -> GameState {
        state.sanitized(for: playerId)
    }
}

