import Foundation
import Combine

// MARK: - Room Configuration
struct RoomConfiguration {
    let maxPlayers: Int
    let turnTimeLimit: TimeInterval
    let reactionTimeLimit: TimeInterval
    let allowSpectators: Bool
    
    static let `default` = RoomConfiguration(
        maxPlayers: 4,
        turnTimeLimit: 60,
        reactionTimeLimit: 5,
        allowSpectators: false
    )
}

// MARK: - Game Room
/// Represents a game room on the server side
final class GameRoom {
    
    // MARK: - Properties
    
    let code: String
    let configuration: RoomConfiguration
    let createdAt: Date
    
    private(set) var engine: GameEngine
    private(set) var playerConnections: [UUID: PlayerConnection] = [:]
    
    var hostPlayerId: UUID {
        engine.state.hostPlayerId
    }
    
    var playerCount: Int {
        engine.state.players.count
    }
    
    var isFull: Bool {
        playerCount >= configuration.maxPlayers
    }
    
    var isEmpty: Bool {
        playerCount == 0
    }
    
    // MARK: - Initialization
    
    init(code: String, hostPlayerId: UUID, configuration: RoomConfiguration = .default) {
        self.code = code
        self.configuration = configuration
        self.createdAt = Date()
        self.engine = GameEngine(roomCode: code, hostPlayerId: hostPlayerId)
    }
    
    // MARK: - Player Management
    
    func addPlayer(_ player: Player, connection: PlayerConnection) -> Result<Void, GameError> {
        guard !isFull else {
            return .failure(.roomFull)
        }
        
        let result = engine.addPlayer(player)
        if case .success = result {
            playerConnections[player.id] = connection
        }
        return result
    }
    
    func removePlayer(_ playerId: UUID) {
        engine.removePlayer(playerId)
        playerConnections.removeValue(forKey: playerId)
    }
    
    func updateConnection(_ playerId: UUID, connection: PlayerConnection) {
        playerConnections[playerId] = connection
    }
    
    // MARK: - Game Actions
    
    func processAction(_ action: GameAction, from playerId: UUID) -> ActionResult {
        switch action {
        case .setReady(let isReady):
            switch engine.setPlayerReady(playerId, isReady: isReady) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .startGame:
            guard playerId == hostPlayerId else {
                return .failure(error: .invalidAction)
            }
            switch engine.startGame() {
            case .success:
                return .success(message: "Game started")
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .peekInitialCard(let position):
            switch engine.peekInitialCard(playerId: playerId, position: position) {
            case .success(let card):
                return .peekResult(card: card, position: position, playerId: playerId)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .finishInitialPeek:
            switch engine.finishInitialPeek(playerId: playerId) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .drawCard(let source):
            switch engine.drawCard(playerId: playerId, from: source) {
            case .success(let card):
                return .peekResult(card: card, position: -1, playerId: playerId)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .replaceCard(let position):
            switch engine.replaceCard(playerId: playerId, at: position) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .discardDrawnCard:
            switch engine.discardDrawnCard(playerId: playerId) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .useAbility:
            switch engine.useAbility(playerId: playerId) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .skipAbility:
            switch engine.skipAbility(playerId: playerId) {
            case .success:
                return .success(message: nil)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .peekOwnCard(let position):
            switch engine.peekOwnCard(playerId: playerId, position: position) {
            case .success(let card):
                return .peekResult(card: card, position: position, playerId: playerId)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .peekOpponentCard(let targetId, let position):
            switch engine.peekOpponentCard(playerId: playerId, targetPlayerId: targetId, position: position) {
            case .success(let card):
                return .peekResult(card: card, position: position, playerId: targetId)
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .swapCards(let myPos, let oppId, let oppPos):
            switch engine.swapCards(playerId: playerId, myPosition: myPos, opponentId: oppId, opponentPosition: oppPos) {
            case .success:
                return .success(message: "Cards swapped")
            case .failure(let error):
                return .failure(error: error)
            }
            
        case .reactWithCard(let position):
            switch engine.reactWithCard(playerId: playerId, position: position) {
            case .success:
                return .reactionAccepted(playerId: playerId)
            case .failure(let error):
                return .reactionRejected(reason: error.localizedDescription)
            }
            
        case .callCabo:
            switch engine.callCabo(playerId: playerId) {
            case .success:
                return .success(message: "Cabo called!")
            case .failure(let error):
                return .failure(error: error)
            }
            
        default:
            return .failure(error: .invalidAction)
        }
    }
    
    // MARK: - Broadcasting
    
    func broadcastState() {
        for (playerId, connection) in playerConnections {
            let sanitizedState = engine.getState(for: playerId)
            let message = NetworkMessage(
                type: .gameStateUpdate,
                payload: .gameStateUpdate(state: sanitizedState)
            )
            connection.send(message)
        }
    }
    
    func sendToPlayer(_ playerId: UUID, message: NetworkMessage) {
        playerConnections[playerId]?.send(message)
    }
    
    func broadcastToAll(except excludedPlayerId: UUID? = nil, message: NetworkMessage) {
        for (playerId, connection) in playerConnections {
            if playerId != excludedPlayerId {
                connection.send(message)
            }
        }
    }
}

// MARK: - Player Connection Protocol
protocol PlayerConnection {
    var playerId: UUID { get }
    var isConnected: Bool { get }
    func send(_ message: NetworkMessage)
    func disconnect()
}

// MARK: - Room Code Generator
struct RoomCodeGenerator {
    private static let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private static let codeLength = 6
    
    static func generate() -> String {
        String((0..<codeLength).map { _ in
            characters.randomElement()!
        })
    }
}

