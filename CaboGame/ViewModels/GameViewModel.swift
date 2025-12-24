import Foundation
import Combine
import SwiftUI

// MARK: - Game View Model
@MainActor
final class GameViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var gameState: GameState?
    @Published private(set) var localPlayerId: UUID?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var errorMessage: String?
    
    // UI State
    @Published var showingPeekCard: Card?
    @Published var peekCardPosition: Int?
    @Published var peekCardOwner: UUID?
    @Published var selectedCardPosition: Int?
    @Published var selectedOpponentId: UUID?
    @Published var selectedOpponentPosition: Int?
    @Published var showingReactionAlert = false
    @Published var showingGameResult: GameResult?
    @Published var pendingReplacePosition: Int? // Two-step replace: selected card waiting for confirmation
    
    // Animation state
    @Published var cardReplaceAnimation: CardReplaceAnimation?
    @Published var cardDiscardAnimation: CardDiscardAnimation?
    @Published var cardDrawAnimation: CardDrawAnimation?
    @Published var cardSwapAnimation: CardSwapAnimation?
    
    // Notifications for other players' actions
    @Published var peekNotification: String?
    @Published var broadcastSwapAnimation: SwapEventAnimation?
    
    // Cache for peeked cards (stores actual card data for animation purposes)
    private var peekedCardCache: [Int: Card] = [:]
    
    // Turn state
    @Published private(set) var turnState: TurnStateMachine?
    @Published private(set) var initialPeekState: InitialPeekStateMachine?
    
    // Timer displays
    @Published private(set) var reactionTimeRemaining: TimeInterval = 0
    @Published private(set) var turnTimeRemaining: TimeInterval = 0
    
    // MARK: - Properties
    
    private let networkManager: WebSocketManager
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    
    // MARK: - Computed Properties
    
    var localPlayer: Player? {
        guard let id = localPlayerId else { return nil }
        return gameState?.player(withId: id)
    }
    
    var opponents: [Player] {
        guard let state = gameState, let localId = localPlayerId else { return [] }
        return state.players.filter { $0.id != localId }
    }
    
    var isMyTurn: Bool {
        gameState?.currentPlayerId == localPlayerId
    }
    
    var currentPhase: GamePhase {
        gameState?.phase ?? .lobby
    }
    
    var canCallCabo: Bool {
        turnState?.canCallCabo ?? false
    }
    
    var isInReactionWindow: Bool {
        gameState?.phase == .reactionWindow
    }
    
    var topDiscardCard: Card? {
        gameState?.topDiscard
    }
    
    var deckCount: Int {
        gameState?.deckCount ?? 0
    }
    
    var drawnCard: Card? {
        gameState?.drawnCard
    }
    
    // MARK: - Initialization
    
    init(networkManager: WebSocketManager = WebSocketManager()) {
        self.networkManager = networkManager
        setupBindings()
    }
    
    private func setupBindings() {
        // Connection state
        networkManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)
        
        // Message handling
        networkManager.messageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessage(message)
            }
            .store(in: &cancellables)
        
        // Error handling
        networkManager.connectionError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connection
    
    func connect(to serverURL: URL = ServerConfig.defaultURL) {
        networkManager.connect(to: serverURL)
    }
    
    func disconnect() {
        networkManager.disconnect()
    }
    
    // MARK: - Room Actions
    
    func createRoom(playerName: String) {
        // Ensure we're connected before creating room
        if connectionState != .connected {
            networkManager.connect()
            // Wait a bit for connection, then create room
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.networkManager.createRoom(hostName: playerName)
            }
        } else {
            networkManager.createRoom(hostName: playerName)
        }
    }
    
    func joinRoom(code: String, playerName: String) {
        // Ensure we're connected before joining room
        if connectionState != .connected {
            networkManager.connect()
            // Wait a bit for connection, then join room
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.networkManager.joinRoom(code: code, playerName: playerName)
            }
        } else {
            networkManager.joinRoom(code: code, playerName: playerName)
        }
    }
    
    func leaveRoom() {
        if let playerId = localPlayerId {
            networkManager.leaveRoom(playerId: playerId)
        }
        networkManager.disconnect()
        resetState()
    }
    
    // MARK: - Game Actions
    
    func setReady(_ isReady: Bool) {
        sendAction(.setReady(isReady: isReady))
    }
    
    func startGame() {
        sendAction(.startGame)
    }
    
    func peekInitialCard(at position: Int) {
        guard initialPeekState?.canPeek(at: position) == true else { return }
        sendAction(.peekInitialCard(position: position))
    }
    
    func finishInitialPeek() {
        sendAction(.finishInitialPeek)
    }
    
    func drawFromDeck() {
        guard turnState?.canPerform(.drawFromDeck) == true else { return }
        HapticFeedback.light()
        sendAction(.drawCard(source: .deck))
    }
    
    func drawFromDiscard() {
        guard turnState?.canPerform(.drawFromDiscard) == true else { return }
        HapticFeedback.light()
        sendAction(.drawCard(source: .discardPile))
    }
    
    func selectCardForReplace(at position: Int) {
        // Two-step replace: first select the card
        guard turnState?.canPerform(.replaceCard(position)) == true else { return }
        HapticFeedback.light()
        pendingReplacePosition = position
    }
    
    func confirmReplace() {
        // Two-step replace: confirm the replacement
        guard let position = pendingReplacePosition else { return }
        guard turnState?.canPerform(.replaceCard(position)) == true else { return }
        guard let drawnCard = drawnCard,
              let player = localPlayer,
              position < player.cards.count else { return }
        
        // Get replaced card - prefer cached peeked card, fall back to current card data
        let cachedCard = peekedCardCache[position]
        let currentCard = player.cards[position].card
        let replacedCard = cachedCard ?? currentCard
        
        print("[Replace] Position \(position): cached=\(cachedCard?.rank.displayValue ?? "nil") of \(cachedCard?.suit.symbol ?? "nil"), current=\(currentCard.rank.displayValue), using=\(replacedCard.rank.displayValue) of \(replacedCard.suit.symbol)")
        print("[Replace] Cache contents: \(peekedCardCache.mapValues { "\($0.rank.displayValue) of \($0.suit)" })")
        
        // Trigger animation
        triggerReplaceAnimation(drawnCard: drawnCard, replacedCard: replacedCard, position: position)
        
        // Remove from cache since card is being replaced
        peekedCardCache.removeValue(forKey: position)
        
        HapticFeedback.medium()
        sendAction(.replaceCard(position: position))
        pendingReplacePosition = nil
    }
    
    func cancelReplace() {
        // Two-step replace: cancel selection
        HapticFeedback.light()
        pendingReplacePosition = nil
    }
    
    func replaceCard(at position: Int) {
        guard turnState?.canPerform(.replaceCard(position)) == true else { return }
        HapticFeedback.medium()
        sendAction(.replaceCard(position: position))
    }
    
    func discardDrawnCard() {
        guard turnState?.canPerform(.discardDrawnCard) == true else { return }
        HapticFeedback.light()
        pendingReplacePosition = nil // Clear any pending selection
        
        // Trigger discard animation
        if let drawnCard = gameState?.drawnCard {
            triggerDiscardAnimation(card: drawnCard)
        }
        
        sendAction(.discardDrawnCard)
    }
    
    func useAbility() {
        guard turnState?.canPerform(.useAbility) == true else { return }
        sendAction(.useAbility)
    }
    
    func skipAbility() {
        guard turnState?.canPerform(.skipAbility) == true else { return }
        sendAction(.skipAbility)
    }
    
    func peekOwnCard(at position: Int) {
        HapticFeedback.light()
        sendAction(.peekOwnCard(position: position))
    }
    
    func peekOpponentCard(playerId: UUID, position: Int) {
        HapticFeedback.light()
        sendAction(.peekOpponentCard(playerId: playerId, position: position))
    }
    
    func swapCards() {
        guard let myPos = selectedCardPosition,
              let oppId = selectedOpponentId,
              let oppPos = selectedOpponentPosition,
              let player = localPlayer,
              let opponent = gameState?.players.first(where: { $0.id == oppId }) else { return }
        
        // Get cards for animation (use cache or current)
        let myCard = peekedCardCache[myPos] ?? player.cards[myPos].card
        let oppCard = opponent.cards[oppPos].card  // We don't know opponent's card
        
        // Trigger swap animation
        triggerSwapAnimation(myCard: myCard, opponentCard: oppCard, myPosition: myPos, opponentName: opponent.name)
        
        HapticFeedback.medium()
        sendAction(.swapCards(myPosition: myPos, opponentId: oppId, opponentPosition: oppPos))
        clearSelections()
    }
    
    func reactWithCard(at position: Int) {
        HapticFeedback.heavy()
        sendAction(.reactWithCard(position: position))
    }
    
    func callCabo() {
        guard canCallCabo else { return }
        HapticFeedback.success()
        sendAction(.callCabo)
    }
    
    private func sendAction(_ action: GameAction) {
        guard let playerId = localPlayerId else { return }
        networkManager.sendAction(action, playerId: playerId)
    }
    
    // MARK: - Card Selection
    
    func selectOwnCard(at position: Int) {
        if selectedCardPosition == position {
            selectedCardPosition = nil
        } else {
            selectedCardPosition = position
        }
    }
    
    func selectOpponentCard(playerId: UUID, position: Int) {
        if selectedOpponentId == playerId && selectedOpponentPosition == position {
            selectedOpponentId = nil
            selectedOpponentPosition = nil
        } else {
            selectedOpponentId = playerId
            selectedOpponentPosition = position
        }
    }
    
    func clearSelections() {
        selectedCardPosition = nil
        selectedOpponentId = nil
        selectedOpponentPosition = nil
    }
    
    func dismissPeek() {
        showingPeekCard = nil
        peekCardPosition = nil
        peekCardOwner = nil
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: NetworkMessage) {
        switch message.payload {
        case .roomCreated(let code, let playerId, let state):
            print("[GameVM] Room created: \(code), playerId: \(playerId), players: \(state.players.count)")
            localPlayerId = playerId
            updateGameState(state)
            initializeStateMachines(playerId: playerId)
            
        case .roomJoined(let playerId, let state):
            localPlayerId = playerId
            updateGameState(state)
            initializeStateMachines(playerId: playerId)
            
        case .gameStateUpdate(let state):
            updateGameState(state)
            
        case .actionResult(let result):
            handleActionResult(result)
            
        case .playerJoined(let player):
            // State update will follow
            HapticFeedback.light()
            
        case .playerLeft(let playerId):
            // State update will follow
            HapticFeedback.warning()
            
        case .playerDisconnected(let playerId):
            // Handle opponent disconnect
            break
            
        case .playerReconnected(let playerId):
            // Handle opponent reconnect
            HapticFeedback.success()
            
        case .error(let error):
            errorMessage = error.localizedDescription
            HapticFeedback.error()
            
        case .swapPerformed(let swapperId, let swapperName, let opponentId, let opponentName, let swapperPosition, let opponentPosition):
            // Show swap animation to all players
            showSwapEvent(swapperId: swapperId, swapperName: swapperName, opponentId: opponentId, opponentName: opponentName, swapperPosition: swapperPosition, opponentPosition: opponentPosition)
            HapticFeedback.light()
            
        case .peekPerformed(let peekerId, let peekerName, let targetId, let targetName, let isOwnCard):
            // Show peek notification to all other players
            if peekerId.lowercased() != localPlayerId?.uuidString.lowercased() {
                // Another player is peeking
                if isOwnCard {
                    peekNotification = "\(peekerName) is peeking at their own card"
                } else {
                    peekNotification = "\(peekerName) is peeking at \(targetName)'s card"
                }
                // Auto-dismiss after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.peekNotification = nil
                }
            }
            
        default:
            break
        }
    }
    
    private func handleActionResult(_ result: ActionResult) {
        switch result {
        case .success(let message):
            if let msg = message {
                print("Action success: \(msg)")
            }
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            HapticFeedback.error()
            
        case .peekResult(let card, let position, let playerId):
            showingPeekCard = card
            peekCardPosition = position
            peekCardOwner = playerId
            
            // Cache the peeked card data for animations (only for own cards)
            if playerId == localPlayerId {
                peekedCardCache[position] = card
            }
            
            // Update initial peek state if applicable
            if currentPhase == .initialPeek && playerId == localPlayerId {
                initialPeekState?.recordPeek(at: position)
            }
            HapticFeedback.light()
            
        case .gameEnded(let result):
            showingGameResult = result
            HapticFeedback.success()
            
        case .reactionAccepted(let playerId):
            if playerId == localPlayerId {
                HapticFeedback.success()
            }
            
        case .reactionRejected(let reason):
            errorMessage = reason
            HapticFeedback.error()
            
        case .stateUpdate(let state):
            updateGameState(state)
        }
    }
    
    private func updateGameState(_ state: GameState) {
        let previousDrawnCard = gameState?.drawnCard
        gameState = state
        
        // Trigger draw animation when a new card is drawn (for current player)
        if let playerId = localPlayerId,
           state.currentPlayerId == playerId,
           let newDrawnCard = state.drawnCard,
           previousDrawnCard == nil {
            triggerDrawAnimation(card: newDrawnCard)
        }
        
        // Update turn state machine
        if let playerId = localPlayerId {
            turnState?.updateFromGameState(state)
            initialPeekState?.updateFromGameState(state)
            
            // Cache peeked cards for animations
            if let player = state.player(withId: playerId) {
                for (index, playerCard) in player.cards.enumerated() {
                    // Cache any card that has valid (non-hidden) data
                    // This includes: face-up cards, peeked cards, auto-peeked bottom cards
                    if playerCard.card.rank != .hidden && playerCard.card.suit != .hidden {
                        peekedCardCache[index] = playerCard.card
                        print("[Cache] Stored card at position \(index): \(playerCard.card.rank.displayValue) of \(playerCard.card.suit)")
                    }
                }
            }
        }
        
        // Update timers
        updateTimers()
    }
    
    private func initializeStateMachines(playerId: UUID) {
        turnState = TurnStateMachine(playerId: playerId)
        initialPeekState = InitialPeekStateMachine(playerId: playerId)
    }
    
    // MARK: - Timer Management
    
    private func updateTimers() {
        guard let state = gameState else { return }
        
        // Cancel existing timer
        timerCancellable?.cancel()
        
        // Set up timer updates
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickTimers()
            }
        
        reactionTimeRemaining = state.reactionTimeRemaining
        turnTimeRemaining = state.turnTimeRemaining
    }
    
    private func tickTimers() {
        guard let state = gameState else { return }
        
        reactionTimeRemaining = state.reactionTimeRemaining
        turnTimeRemaining = state.turnTimeRemaining
        
        // Show reaction alert to ALL players during reaction window
        if isInReactionWindow && localPlayer != nil {
            showingReactionAlert = true
        } else {
            showingReactionAlert = false
        }
    }
    
    // MARK: - State Reset
    
    private func resetState() {
        gameState = nil
        localPlayerId = nil
        turnState = nil
        initialPeekState = nil
        clearSelections()
        dismissPeek()
        pendingReplacePosition = nil
        cardReplaceAnimation = nil
        cardDiscardAnimation = nil
        cardDrawAnimation = nil
        cardSwapAnimation = nil
        peekedCardCache.removeAll()
        showingGameResult = nil
        errorMessage = nil
    }
    
    // MARK: - Animation Helpers
    
    func triggerReplaceAnimation(drawnCard: Card, replacedCard: Card, position: Int) {
        cardReplaceAnimation = CardReplaceAnimation(
            drawnCard: drawnCard,
            replacedCard: replacedCard,
            targetPosition: position
        )
        
        // Clear animation after it completes (much slower = 2.5s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.cardReplaceAnimation = nil
        }
    }
    
    func triggerDiscardAnimation(card: Card) {
        cardDiscardAnimation = CardDiscardAnimation(card: card)
        
        // Clear animation after it completes (1.5s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.cardDiscardAnimation = nil
        }
    }
    
    func triggerDrawAnimation(card: Card) {
        cardDrawAnimation = CardDrawAnimation(card: card)
        
        // Clear animation after it completes (1.2s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.cardDrawAnimation = nil
        }
    }
    
    func triggerSwapAnimation(myCard: Card, opponentCard: Card, myPosition: Int, opponentName: String) {
        cardSwapAnimation = CardSwapAnimation(
            myCard: myCard,
            opponentCard: opponentCard,
            myPosition: myPosition,
            opponentName: opponentName
        )
        
        // Clear animation after it completes (2.0s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.cardSwapAnimation = nil
        }
    }
    
    func showSwapEvent(swapperId: String, swapperName: String, opponentId: String, opponentName: String, swapperPosition: Int, opponentPosition: Int) {
        // Don't show animation to the player who initiated the swap (they already see their own animation)
        if swapperId.lowercased() == localPlayerId?.uuidString.lowercased() {
            return
        }
        
        broadcastSwapAnimation = SwapEventAnimation(
            swapperName: swapperName,
            opponentName: opponentName,
            swapperId: swapperId,
            opponentId: opponentId,
            swapperPosition: swapperPosition,
            opponentPosition: opponentPosition
        )
        
        // Clear animation after it completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.broadcastSwapAnimation = nil
        }
    }
}

// MARK: - Animation Models

struct CardReplaceAnimation: Identifiable {
    let id = UUID()
    let drawnCard: Card
    let replacedCard: Card
    let targetPosition: Int
}

struct CardDiscardAnimation: Identifiable {
    let id = UUID()
    let card: Card
}

struct CardDrawAnimation: Identifiable {
    let id = UUID()
    let card: Card
}

struct CardSwapAnimation: Identifiable {
    let id = UUID()
    let myCard: Card
    let opponentCard: Card
    let myPosition: Int
    let opponentName: String
}

struct SwapEventAnimation: Identifiable {
    let id = UUID()
    let swapperName: String
    let opponentName: String
    let swapperId: String
    let opponentId: String
    let swapperPosition: Int
    let opponentPosition: Int
}

