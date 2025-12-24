import Foundation

// MARK: - Network Message Types
enum MessageType: String, Codable {
    // Client -> Server
    case createRoom
    case joinRoom
    case leaveRoom
    case playerAction
    case heartbeat
    case reconnect
    
    // Server -> Client
    case roomCreated
    case roomJoined
    case playerJoined
    case playerLeft
    case gameStateUpdate
    case actionResult
    case error
    case pong
    case playerReconnected
    case playerDisconnected
    case swapPerformed
    case peekPerformed
}

// MARK: - Network Message
struct NetworkMessage: Codable {
    let type: MessageType
    let timestamp: String? // Keep as string to avoid date parsing issues
    let payload: MessagePayload
    
    init(type: MessageType, payload: MessagePayload) {
        self.type = type
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.payload = payload
    }
}

// MARK: - Message Payload
enum MessagePayload: Codable {
    // Room management
    case createRoom(hostName: String)
    case joinRoom(roomCode: String, playerName: String)
    case roomCreated(roomCode: String, playerId: UUID, gameState: GameState)
    case roomJoined(playerId: UUID, gameState: GameState)
    case leaveRoom(playerId: UUID)
    case playerJoined(player: Player)
    case playerLeft(playerId: UUID)
    
    // Game actions
    case action(playerId: UUID, action: GameAction)
    case actionResult(result: ActionResult)
    case gameStateUpdate(state: GameState)
    
    // Connection
    case heartbeat(playerId: UUID)
    case pong
    case reconnect(playerId: UUID, roomCode: String)
    case playerReconnected(playerId: UUID)
    case playerDisconnected(playerId: UUID)
    
    // Ability events
    case swapPerformed(swapperId: String, swapperName: String, opponentId: String, opponentName: String, swapperPosition: Int, opponentPosition: Int)
    case peekPerformed(peekerId: String, peekerName: String, targetId: String, targetName: String, isOwnCard: Bool)
    
    // Error
    case error(GameError)
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type
        case hostName, roomCode, playerName, playerId
        case gameState, state, player, action, result
        case swapperId, swapperName, opponentId, opponentName, swapperPosition, opponentPosition
        case peekerId, peekerName, targetId, targetName, isOwnCard
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "createRoom":
            let name = try container.decode(String.self, forKey: .hostName)
            self = .createRoom(hostName: name)
            
        case "joinRoom":
            let code = try container.decode(String.self, forKey: .roomCode)
            let name = try container.decode(String.self, forKey: .playerName)
            self = .joinRoom(roomCode: code, playerName: name)
            
        case "roomCreated":
            let code = try container.decode(String.self, forKey: .roomCode)
            let pid = try container.decode(UUID.self, forKey: .playerId)
            let state = try container.decode(GameState.self, forKey: .gameState)
            self = .roomCreated(roomCode: code, playerId: pid, gameState: state)
            
        case "roomJoined":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            let state = try container.decode(GameState.self, forKey: .gameState)
            self = .roomJoined(playerId: pid, gameState: state)
            
        case "leaveRoom":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .leaveRoom(playerId: pid)
            
        case "playerJoined":
            let player = try container.decode(Player.self, forKey: .player)
            self = .playerJoined(player: player)
            
        case "playerLeft":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .playerLeft(playerId: pid)
            
        case "action":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            let action = try container.decode(GameAction.self, forKey: .action)
            self = .action(playerId: pid, action: action)
            
        case "actionResult":
            let result = try container.decode(ActionResult.self, forKey: .result)
            self = .actionResult(result: result)
            
        case "gameStateUpdate":
            let state = try container.decode(GameState.self, forKey: .state)
            self = .gameStateUpdate(state: state)
            
        case "heartbeat":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .heartbeat(playerId: pid)
            
        case "pong":
            self = .pong
            
        case "reconnect":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            let code = try container.decode(String.self, forKey: .roomCode)
            self = .reconnect(playerId: pid, roomCode: code)
            
        case "playerReconnected":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .playerReconnected(playerId: pid)
            
        case "playerDisconnected":
            let pid = try container.decode(UUID.self, forKey: .playerId)
            self = .playerDisconnected(playerId: pid)
            
        case "swapPerformed":
            let swapperId = try container.decode(String.self, forKey: .swapperId)
            let swapperName = try container.decode(String.self, forKey: .swapperName)
            let opponentId = try container.decode(String.self, forKey: .opponentId)
            let opponentName = try container.decode(String.self, forKey: .opponentName)
            let swapperPosition = try container.decode(Int.self, forKey: .swapperPosition)
            let opponentPosition = try container.decode(Int.self, forKey: .opponentPosition)
            self = .swapPerformed(swapperId: swapperId, swapperName: swapperName, opponentId: opponentId, opponentName: opponentName, swapperPosition: swapperPosition, opponentPosition: opponentPosition)
            
        case "peekPerformed":
            let peekerId = try container.decode(String.self, forKey: .peekerId)
            let peekerName = try container.decode(String.self, forKey: .peekerName)
            let targetId = try container.decode(String.self, forKey: .targetId)
            let targetName = try container.decode(String.self, forKey: .targetName)
            let isOwnCard = try container.decode(Bool.self, forKey: .isOwnCard)
            self = .peekPerformed(peekerId: peekerId, peekerName: peekerName, targetId: targetId, targetName: targetName, isOwnCard: isOwnCard)
            
        case "error":
            let err = try container.decode(GameError.self, forKey: .result)
            self = .error(err)
            
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown payload type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .createRoom(let name):
            try container.encode("createRoom", forKey: .type)
            try container.encode(name, forKey: .hostName)
            
        case .joinRoom(let code, let name):
            try container.encode("joinRoom", forKey: .type)
            try container.encode(code, forKey: .roomCode)
            try container.encode(name, forKey: .playerName)
            
        case .roomCreated(let code, let pid, let state):
            try container.encode("roomCreated", forKey: .type)
            try container.encode(code, forKey: .roomCode)
            try container.encode(pid, forKey: .playerId)
            try container.encode(state, forKey: .gameState)
            
        case .roomJoined(let pid, let state):
            try container.encode("roomJoined", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            try container.encode(state, forKey: .gameState)
            
        case .leaveRoom(let pid):
            try container.encode("leaveRoom", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            
        case .playerJoined(let player):
            try container.encode("playerJoined", forKey: .type)
            try container.encode(player, forKey: .player)
            
        case .playerLeft(let pid):
            try container.encode("playerLeft", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            
        case .action(let pid, let action):
            try container.encode("action", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            try container.encode(action, forKey: .action)
            
        case .actionResult(let result):
            try container.encode("actionResult", forKey: .type)
            try container.encode(result, forKey: .result)
            
        case .gameStateUpdate(let state):
            try container.encode("gameStateUpdate", forKey: .type)
            try container.encode(state, forKey: .state)
            
        case .heartbeat(let pid):
            try container.encode("heartbeat", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            
        case .pong:
            try container.encode("pong", forKey: .type)
            
        case .reconnect(let pid, let code):
            try container.encode("reconnect", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            try container.encode(code, forKey: .roomCode)
            
        case .playerReconnected(let pid):
            try container.encode("playerReconnected", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            
        case .playerDisconnected(let pid):
            try container.encode("playerDisconnected", forKey: .type)
            try container.encode(pid, forKey: .playerId)
            
        case .swapPerformed(let swapperId, let swapperName, let opponentId, let opponentName, let swapperPosition, let opponentPosition):
            try container.encode("swapPerformed", forKey: .type)
            try container.encode(swapperId, forKey: .swapperId)
            try container.encode(swapperName, forKey: .swapperName)
            try container.encode(opponentId, forKey: .opponentId)
            try container.encode(opponentName, forKey: .opponentName)
            try container.encode(swapperPosition, forKey: .swapperPosition)
            try container.encode(opponentPosition, forKey: .opponentPosition)
            
        case .peekPerformed(let peekerId, let peekerName, let targetId, let targetName, let isOwnCard):
            try container.encode("peekPerformed", forKey: .type)
            try container.encode(peekerId, forKey: .peekerId)
            try container.encode(peekerName, forKey: .peekerName)
            try container.encode(targetId, forKey: .targetId)
            try container.encode(targetName, forKey: .targetName)
            try container.encode(isOwnCard, forKey: .isOwnCard)
            
        case .error(let err):
            try container.encode("error", forKey: .type)
            try container.encode(err, forKey: .result)
        }
    }
}

