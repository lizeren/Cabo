import Foundation
import Combine

// MARK: - Connection State
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

// MARK: - WebSocket Manager
/// Handles WebSocket connection to game server
final class WebSocketManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var latency: TimeInterval = 0
    
    // MARK: - Publishers
    
    let messageReceived = PassthroughSubject<NetworkMessage, Never>()
    let connectionError = PassthroughSubject<Error, Never>()
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var serverURL: URL?
    private var playerId: UUID?
    private var roomCode: String?
    
    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var lastPingTime: Date?
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Connection Management
    
    func connect(to url: URL, playerId: UUID? = nil, roomCode: String? = nil) {
        self.serverURL = url
        self.playerId = playerId
        self.roomCode = roomCode
        
        connectionState = .connecting
        
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        startReceiving()
        startHeartbeat()
    }
    
    func disconnect() {
        stopHeartbeat()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionState = .disconnected
        reconnectAttempts = 0
    }
    
    func connect() {
        // Use the default server URL or last used URL
        let url = serverURL ?? URL(string: "ws://\(GameConstants.serverIP):8080/ws")!
        connect(to: url)
    }
    
    private func reconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let url = serverURL else {
            connectionState = .failed(reason: "Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)
        
        // Exponential backoff
        let delay = Double(min(reconnectAttempts * 2, 10))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.connect(to: url, playerId: self.playerId, roomCode: self.roomCode)
        }
    }
    
    // MARK: - Message Sending
    
    func send(_ message: NetworkMessage) {
        guard connectionState == .connected else { return }
        
        do {
            let data = try encoder.encode(message)
            let wsMessage = URLSessionWebSocketTask.Message.data(data)
            
            webSocket?.send(wsMessage) { [weak self] error in
                if let error = error {
                    self?.connectionError.send(error)
                }
            }
        } catch {
            connectionError.send(error)
        }
    }
    
    func sendAction(_ action: GameAction, playerId: UUID) {
        let message = NetworkMessage(
            type: .playerAction,
            payload: .action(playerId: playerId, action: action)
        )
        send(message)
    }
    
    func createRoom(hostName: String) {
        let message = NetworkMessage(
            type: .createRoom,
            payload: .createRoom(hostName: hostName)
        )
        send(message)
    }
    
    func joinRoom(code: String, playerName: String) {
        let message = NetworkMessage(
            type: .joinRoom,
            payload: .joinRoom(roomCode: code, playerName: playerName)
        )
        send(message)
    }
    
    func leaveRoom(playerId: UUID) {
        let message = NetworkMessage(
            type: .leaveRoom,
            payload: .leaveRoom(playerId: playerId)
        )
        send(message)
    }
    
    // MARK: - Message Receiving
    
    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleWebSocketMessage(message)
                // Continue receiving
                self.startReceiving()
                
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }
        
        // Debug: print raw message
        if let str = String(data: data, encoding: .utf8) {
            print("[WebSocket] RAW: \(str.prefix(1000))")
        }
        
        do {
            let networkMessage = try decoder.decode(NetworkMessage.self, from: data)
            print("[WebSocket] Decoded message type: \(networkMessage.type)")
            
            // Handle pong for latency calculation
            if case .pong = networkMessage.payload {
                if let pingTime = lastPingTime {
                    latency = Date().timeIntervalSince(pingTime)
                }
            }
            
            // Handle reconnection confirmation
            if case .playerReconnected = networkMessage.payload {
                reconnectAttempts = 0
            }
            
            messageReceived.send(networkMessage)
        } catch let decodingError as DecodingError {
            print("[WebSocket] DECODING ERROR: \(decodingError)")
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("  Key '\(key.stringValue)' not found: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                print("  Type mismatch for \(type): \(context.debugDescription)")
                print("  Coding path: \(context.codingPath.map { $0.stringValue })")
            case .valueNotFound(let type, let context):
                print("  Value not found for \(type): \(context.debugDescription)")
            case .dataCorrupted(let context):
                print("  Data corrupted: \(context.debugDescription)")
            @unknown default:
                print("  Unknown decoding error")
            }
        } catch {
            print("[WebSocket] OTHER ERROR: \(error)")
        }
    }
    
    private func handleError(_ error: Error) {
        connectionError.send(error)
        
        // Attempt reconnection for recoverable errors
        if connectionState == .connected {
            connectionState = .disconnected
            reconnect()
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        guard let pid = playerId else { return }
        
        lastPingTime = Date()
        let message = NetworkMessage(
            type: .heartbeat,
            payload: .heartbeat(playerId: pid)
        )
        send(message)
    }
    
    // MARK: - Reconnection
    
    func attemptReconnection(playerId: UUID, roomCode: String) {
        self.playerId = playerId
        self.roomCode = roomCode
        
        guard connectionState == .connected else {
            reconnect()
            return
        }
        
        let message = NetworkMessage(
            type: .reconnect,
            payload: .reconnect(playerId: playerId, roomCode: roomCode)
        )
        send(message)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        connectionState = .connected
        reconnectAttempts = 0
        
        // If we have reconnection info, attempt to rejoin
        if let pid = playerId, let code = roomCode {
            attemptReconnection(playerId: pid, roomCode: code)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        connectionState = .disconnected
        
        // Attempt reconnection if not a normal closure
        if closeCode != .normalClosure {
            reconnect()
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            handleError(error)
        }
    }
}

// MARK: - Server Configuration
struct ServerConfig {
    // Change this to your Mac's IP address for iPhone testing
    // Find your IP with: ipconfig getifaddr en0
    static let defaultHost = "10.0.0.49"
    static let defaultPort = 8080
    static let websocketPath = "/ws"
    
    static var defaultURL: URL {
        URL(string: "ws://\(defaultHost):\(defaultPort)\(websocketPath)")!
    }
    
    static func url(host: String, port: Int) -> URL {
        URL(string: "ws://\(host):\(port)\(websocketPath)")!
    }
}

