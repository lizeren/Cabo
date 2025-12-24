import Foundation
import Combine

// MARK: - Turn State
enum TurnState: Equatable {
    case notStarted
    case waitingForTurn
    case mustDraw
    case decidingAction(drawnCard: Card)
    case choosingAbilityTarget(ability: CardAbility)
    case waitingForReaction
    case turnComplete
}

// MARK: - Turn Event
enum TurnEvent {
    case turnStarted
    case cardDrawn(Card)
    case cardReplaced
    case cardDiscarded
    case abilityChosen
    case abilitySkipped
    case targetSelected
    case reactionWindowStarted
    case reactionWindowEnded
    case turnEnded
    case caboCalledBy(UUID)
}

// MARK: - Turn State Machine
/// Manages the state transitions for a player's turn
final class TurnStateMachine: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentState: TurnState = .notStarted
    @Published private(set) var isMyTurn: Bool = false
    @Published private(set) var canCallCabo: Bool = false
    @Published private(set) var availableActions: Set<AvailableAction> = []
    
    // MARK: - Properties
    
    private let playerId: UUID
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Available Actions
    
    enum AvailableAction: Hashable {
        case drawFromDeck
        case drawFromDiscard
        case replaceCard(Int) // Position
        case discardDrawnCard
        case useAbility
        case skipAbility
        case selectOwnCard(Int)
        case selectOpponentCard(UUID, Int)
        case swapCards
        case callCabo
        case react(Int) // Position of matching card
    }
    
    // MARK: - Initialization
    
    init(playerId: UUID) {
        self.playerId = playerId
    }
    
    // MARK: - State Updates
    
    func updateFromGameState(_ gameState: GameState) {
        isMyTurn = gameState.currentPlayerId == playerId
        
        // Determine current state based on game state
        switch gameState.phase {
        case .lobby, .initialPeek:
            currentState = .notStarted
            availableActions = []
            canCallCabo = false
            
        case .playing, .finalRound:
            updatePlayingState(gameState)
            
        case .reactionWindow:
            updateReactionState(gameState)
            
        case .scoring, .gameOver:
            currentState = .turnComplete
            availableActions = []
            canCallCabo = false
        }
    }
    
    private func updatePlayingState(_ gameState: GameState) {
        guard isMyTurn else {
            currentState = .waitingForTurn
            availableActions = []
            canCallCabo = false
            return
        }
        
        var actions = Set<AvailableAction>()
        
        switch gameState.turnPhase {
        case .drawing:
            // Auto-draw happens on server, wait for deciding phase
            currentState = .waitingForTurn
            canCallCabo = false
            
        case .deciding:
            if let card = gameState.drawnCard {
                currentState = .decidingAction(drawnCard: card)
                
                // Can replace any card in hand
                let cardCount = gameState.player(withId: playerId)?.cards.count ?? 4
                for i in 0..<cardCount {
                    actions.insert(.replaceCard(i))
                }
                actions.insert(.discardDrawnCard)
                
                // Can call Cabo during deciding phase (before playing)
                if gameState.caboCallerId == nil && gameState.phase == .playing {
                    canCallCabo = true
                    actions.insert(.callCabo)
                } else {
                    canCallCabo = false
                }
            } else {
                canCallCabo = false
            }
            
        case .usingAbility:
            if let topCard = gameState.topDiscard {
                currentState = .choosingAbilityTarget(ability: topCard.ability)
                actions.insert(.useAbility)
                actions.insert(.skipAbility)
            }
            canCallCabo = false
            
        case .selectingTarget:
            if let topCard = gameState.topDiscard {
                currentState = .choosingAbilityTarget(ability: topCard.ability)
                
                // Always allow skip during target selection
                actions.insert(.skipAbility)
                
                switch topCard.ability {
                case .peekOwn:
                    // Can peek at any own card
                    for i in 0..<4 {
                        actions.insert(.selectOwnCard(i))
                    }
                    
                case .peekOther:
                    // Can peek at any opponent's card
                    for player in gameState.players where player.id != playerId {
                        for i in 0..<player.cards.count {
                            actions.insert(.selectOpponentCard(player.id, i))
                        }
                    }
                    
                case .swap:
                    actions.insert(.swapCards)
                    
                case .none:
                    break
                }
            }
            canCallCabo = false
            
        case .discarding, .waiting:
            currentState = .waitingForTurn
            canCallCabo = false
        }
        
        availableActions = actions
    }
    
    private func updateReactionState(_ gameState: GameState) {
        currentState = .waitingForReaction
        canCallCabo = false
        
        // ALL players can react (including current player)
        // Wrong guesses result in penalty (extra card)
        guard let player = gameState.player(withId: playerId) else {
            availableActions = []
            return
        }
        
        var actions = Set<AvailableAction>()
        
        // Can react with ANY card (penalty for wrong guess)
        for (index, _) in player.cards.enumerated() {
            actions.insert(.react(index))
        }
        
        availableActions = actions
    }
    
    // MARK: - Action Validation
    
    func canPerform(_ action: AvailableAction) -> Bool {
        availableActions.contains(action)
    }
    
    func validateAction(_ action: GameAction, in gameState: GameState) -> GameError? {
        switch action {
        case .drawCard(let source):
            switch source {
            case .deck:
                return canPerform(.drawFromDeck) ? nil : .invalidAction
            case .discardPile:
                return canPerform(.drawFromDiscard) ? nil : .invalidAction
            }
            
        case .replaceCard(let position):
            return canPerform(.replaceCard(position)) ? nil : .invalidAction
            
        case .discardDrawnCard:
            return canPerform(.discardDrawnCard) ? nil : .invalidAction
            
        case .useAbility:
            return canPerform(.useAbility) ? nil : .invalidAction
            
        case .skipAbility:
            return canPerform(.skipAbility) ? nil : .invalidAction
            
        case .callCabo:
            return canPerform(.callCabo) ? nil : .cannotCallCaboNow
            
        case .reactWithCard(let position):
            return canPerform(.react(position)) ? nil : .cardDoesNotMatch
            
        default:
            return nil
        }
    }
}

// MARK: - Initial Peek State Machine
final class InitialPeekStateMachine: ObservableObject {
    
    @Published private(set) var peeksRemaining: Int = 2
    @Published private(set) var peekedPositions: Set<Int> = []
    @Published private(set) var isComplete: Bool = false
    
    private let playerId: UUID
    
    init(playerId: UUID) {
        self.playerId = playerId
    }
    
    func updateFromGameState(_ gameState: GameState) {
        guard let player = gameState.player(withId: playerId) else { return }
        
        peeksRemaining = player.peeksRemaining
        isComplete = player.peeksRemaining == 0
    }
    
    func recordPeek(at position: Int) {
        peekedPositions.insert(position)
        peeksRemaining = max(0, peeksRemaining - 1)
        isComplete = peeksRemaining == 0
    }
    
    func canPeek(at position: Int) -> Bool {
        guard peeksRemaining > 0 else { return false }
        return !peekedPositions.contains(position)
    }
    
    func reset() {
        peeksRemaining = 2
        peekedPositions = []
        isComplete = false
    }
}

