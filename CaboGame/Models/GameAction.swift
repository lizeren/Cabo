import Foundation

// MARK: - Game Action Types
enum GameAction: Codable, Equatable {
    // Lobby actions
    case joinRoom(playerName: String)
    case leaveRoom
    case setReady(isReady: Bool)
    case startGame
    
    // Initial peek phase
    case peekInitialCard(position: Int)
    case finishInitialPeek
    
    // Turn actions
    case drawCard(source: DrawSource)
    case replaceCard(position: Int)
    case discardDrawnCard
    case useAbility
    case skipAbility
    
    // Ability targets
    case peekOwnCard(position: Int)
    case peekOpponentCard(playerId: UUID, position: Int)
    case swapCards(myPosition: Int, opponentId: UUID, opponentPosition: Int)
    
    // Reaction
    case reactWithCard(position: Int) // Position of matching card in hand
    case passReaction
    
    // Cabo
    case callCabo
    
    // Utility
    case requestGameState
    case ping
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type
        case playerName
        case isReady
        case position
        case source
        case playerId
        case myPosition
        case opponentId
        case opponentPosition
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "joinRoom":
            let name = try container.decode(String.self, forKey: .playerName)
            self = .joinRoom(playerName: name)
        case "leaveRoom":
            self = .leaveRoom
        case "setReady":
            let ready = try container.decode(Bool.self, forKey: .isReady)
            self = .setReady(isReady: ready)
        case "startGame":
            self = .startGame
        case "peekInitialCard":
            let pos = try container.decode(Int.self, forKey: .position)
            self = .peekInitialCard(position: pos)
        case "finishInitialPeek":
            self = .finishInitialPeek
        case "drawCard":
            let src = try container.decode(DrawSource.self, forKey: .source)
            self = .drawCard(source: src)
        case "replaceCard":
            let pos = try container.decode(Int.self, forKey: .position)
            self = .replaceCard(position: pos)
        case "discardDrawnCard":
            self = .discardDrawnCard
        case "useAbility":
            self = .useAbility
        case "skipAbility":
            self = .skipAbility
        case "peekOwnCard":
            let pos = try container.decode(Int.self, forKey: .position)
            self = .peekOwnCard(position: pos)
        case "peekOpponentCard":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            let pos = try container.decode(Int.self, forKey: .position)
            self = .peekOpponentCard(playerId: pid, position: pos)
        case "swapCards":
            let myPos = try container.decode(Int.self, forKey: .myPosition)
            let oppId = try container.decode(UUID.self, forKey: .opponentId)
            let oppPos = try container.decode(Int.self, forKey: .opponentPosition)
            self = .swapCards(myPosition: myPos, opponentId: oppId, opponentPosition: oppPos)
        case "reactWithCard":
            let pos = try container.decode(Int.self, forKey: .position)
            self = .reactWithCard(position: pos)
        case "passReaction":
            self = .passReaction
        case "callCabo":
            self = .callCabo
        case "requestGameState":
            self = .requestGameState
        case "ping":
            self = .ping
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .joinRoom(let name):
            try container.encode("joinRoom", forKey: .type)
            try container.encode(name, forKey: .playerName)
        case .leaveRoom:
            try container.encode("leaveRoom", forKey: .type)
        case .setReady(let ready):
            try container.encode("setReady", forKey: .type)
            try container.encode(ready, forKey: .isReady)
        case .startGame:
            try container.encode("startGame", forKey: .type)
        case .peekInitialCard(let pos):
            try container.encode("peekInitialCard", forKey: .type)
            try container.encode(pos, forKey: .position)
        case .finishInitialPeek:
            try container.encode("finishInitialPeek", forKey: .type)
        case .drawCard(let src):
            try container.encode("drawCard", forKey: .type)
            try container.encode(src, forKey: .source)
        case .replaceCard(let pos):
            try container.encode("replaceCard", forKey: .type)
            try container.encode(pos, forKey: .position)
        case .discardDrawnCard:
            try container.encode("discardDrawnCard", forKey: .type)
        case .useAbility:
            try container.encode("useAbility", forKey: .type)
        case .skipAbility:
            try container.encode("skipAbility", forKey: .type)
        case .peekOwnCard(let pos):
            try container.encode("peekOwnCard", forKey: .type)
            try container.encode(pos, forKey: .position)
        case .peekOpponentCard(let pid, let pos):
            try container.encode("peekOpponentCard", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            try container.encode(pos, forKey: .position)
        case .swapCards(let myPos, let oppId, let oppPos):
            try container.encode("swapCards", forKey: .type)
            try container.encode(myPos, forKey: .myPosition)
            try container.encode(oppId, forKey: .opponentId)
            try container.encode(oppPos, forKey: .opponentPosition)
        case .reactWithCard(let pos):
            try container.encode("reactWithCard", forKey: .type)
            try container.encode(pos, forKey: .position)
        case .passReaction:
            try container.encode("passReaction", forKey: .type)
        case .callCabo:
            try container.encode("callCabo", forKey: .type)
        case .requestGameState:
            try container.encode("requestGameState", forKey: .type)
        case .ping:
            try container.encode("ping", forKey: .type)
        }
    }
}

// MARK: - Action Result
enum ActionResult: Codable {
    case success(message: String?)
    case failure(error: GameError)
    case stateUpdate(GameState)
    case peekResult(card: Card, position: Int, playerId: UUID)
    case gameEnded(result: GameResult)
    case reactionAccepted(playerId: UUID)
    case reactionRejected(reason: String)
    
    enum CodingKeys: String, CodingKey {
        case type, message, error, state, card, position, playerId, result, reason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "success":
            let msg = try container.decodeIfPresent(String.self, forKey: .message)
            self = .success(message: msg)
        case "failure":
            let err = try container.decode(GameError.self, forKey: .error)
            self = .failure(error: err)
        case "stateUpdate":
            let state = try container.decode(GameState.self, forKey: .state)
            self = .stateUpdate(state)
        case "peekResult":
            let card = try container.decode(Card.self, forKey: .card)
            let pos = try container.decode(Int.self, forKey: .position)
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .peekResult(card: card, position: pos, playerId: pid)
        case "gameEnded":
            let result = try container.decode(GameResult.self, forKey: .result)
            self = .gameEnded(result: result)
        case "reactionAccepted":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .reactionAccepted(playerId: pid)
        case "reactionRejected":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .reactionRejected(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown result type"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .success(let msg):
            try container.encode("success", forKey: .type)
            try container.encodeIfPresent(msg, forKey: .message)
        case .failure(let err):
            try container.encode("failure", forKey: .type)
            try container.encode(err, forKey: .error)
        case .stateUpdate(let state):
            try container.encode("stateUpdate", forKey: .type)
            try container.encode(state, forKey: .state)
        case .peekResult(let card, let pos, let pid):
            try container.encode("peekResult", forKey: .type)
            try container.encode(card, forKey: .card)
            try container.encode(pos, forKey: .position)
            try container.encode(pid, forKey: .playerId)
        case .gameEnded(let result):
            try container.encode("gameEnded", forKey: .type)
            try container.encode(result, forKey: .result)
        case .reactionAccepted(let pid):
            try container.encode("reactionAccepted", forKey: .type)
            try container.encode(pid, forKey: .playerId)
        case .reactionRejected(let reason):
            try container.encode("reactionRejected", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Game Error
enum GameError: String, Codable, Error {
    case notYourTurn
    case invalidAction
    case invalidCardPosition
    case invalidPlayer
    case noCardDrawn
    case abilityNotAvailable
    case reactionWindowClosed
    case cardDoesNotMatch
    case gameNotStarted
    case gameAlreadyStarted
    case roomFull
    case roomNotFound
    case notEnoughPlayers
    case alreadyCalledCabo
    case cannotCallCaboNow
    case disconnected
    case serverError
    
    var localizedDescription: String {
        switch self {
        case .notYourTurn: return "It's not your turn"
        case .invalidAction: return "Invalid action"
        case .invalidCardPosition: return "Invalid card position"
        case .invalidPlayer: return "Invalid player"
        case .noCardDrawn: return "You must draw a card first"
        case .abilityNotAvailable: return "This card has no special ability"
        case .reactionWindowClosed: return "Reaction window has closed"
        case .cardDoesNotMatch: return "Card rank doesn't match"
        case .gameNotStarted: return "Game hasn't started yet"
        case .gameAlreadyStarted: return "Game has already started"
        case .roomFull: return "Room is full"
        case .roomNotFound: return "Room not found"
        case .notEnoughPlayers: return "Not enough players to start"
        case .alreadyCalledCabo: return "Cabo has already been called"
        case .cannotCallCaboNow: return "Cannot call Cabo at this time"
        case .disconnected: return "Lost connection to server"
        case .serverError: return "Server error occurred"
        }
    }
}

