import SwiftUI

// MARK: - Lobby View
struct LobbyView: View {
    @ObservedObject var viewModel: GameViewModel
    @State private var playerName = ""
    @State private var roomCode = ""
    @State private var showingJoinRoom = false
    @State private var isConnecting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Spacer()
            
            // Content based on state
            if viewModel.gameState == nil {
                // Not in a room yet
                joinOrCreateSection
            } else {
                // In a room
                roomSection
            }
            
            Spacer()
            
            // Connection status
            connectionStatusBar
        }
        .background(backgroundGradient)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo / Title
            VStack(spacing: 8) {
                Text("CABO")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeColors.primary, ThemeColors.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("The Memory Card Game")
                    .font(Typography.subtitle)
                    .foregroundColor(ThemeColors.textSecondary)
            }
            .padding(.top, 60)
        }
    }
    
    // MARK: - Join or Create Section
    
    private var joinOrCreateSection: some View {
        VStack(spacing: 24) {
            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Name")
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.textSecondary)
                
                TextField("Enter your name", text: $playerName)
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textPrimary)
                    .padding()
                    .background(ThemeColors.cardBack)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ThemeColors.primary.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Create room button
            Button(action: createRoom) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Room")
                }
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: LayoutConstants.buttonHeight)
                .background(ThemeColors.buttonGradient)
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
            }
            .disabled(playerName.isEmpty || isConnecting)
            .opacity(playerName.isEmpty ? 0.5 : 1)
            
            // Divider
            HStack {
                Rectangle()
                    .fill(ThemeColors.textMuted.opacity(0.3))
                    .frame(height: 1)
                
                Text("or")
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.textMuted)
                
                Rectangle()
                    .fill(ThemeColors.textMuted.opacity(0.3))
                    .frame(height: 1)
            }
            
            // Join room section
            if showingJoinRoom {
                joinRoomInput
            } else {
                Button(action: { showingJoinRoom = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                        Text("Join Room")
                    }
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: LayoutConstants.buttonHeight)
                    .background(ThemeColors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius)
                            .stroke(ThemeColors.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(playerName.isEmpty)
                .opacity(playerName.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
    }
    
    private var joinRoomInput: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Room Code")
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.textSecondary)
                
                TextField("Enter room code", text: $roomCode)
                    .font(Typography.roomCode)
                    .foregroundColor(ThemeColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(ThemeColors.cardBack)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ThemeColors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: roomCode) { _, newValue in
                        roomCode = String(newValue.uppercased().prefix(10))
                    }
            }
            
            HStack(spacing: 12) {
                Button(action: { showingJoinRoom = false }) {
                    Text("Cancel")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ThemeColors.cardBack)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Button(action: joinRoom) {
                    Text("Join")
                        .font(Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(!roomCode.isEmpty ? ThemeColors.buttonGradient : LinearGradient(colors: [ThemeColors.cardBack], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(roomCode.isEmpty || isConnecting)
            }
        }
    }
    
    // MARK: - Room Section
    
    private var roomSection: some View {
        VStack(spacing: 24) {
            // Room code display
            if let state = viewModel.gameState {
                VStack(spacing: 8) {
                    Text("Room Code")
                        .font(Typography.caption)
                        .foregroundColor(ThemeColors.textSecondary)
                    
                    Text(state.roomCode)
                        .font(Typography.roomCode)
                        .foregroundColor(ThemeColors.primary)
                        .tracking(4)
                    
                    Button(action: copyRoomCode) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .padding()
                .background(ThemeColors.cardBack.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Players list
            playersListView
            
            // Ready / Start buttons
            if let player = viewModel.localPlayer {
                if player.isHost {
                    hostControls
                } else {
                    guestControls
                }
            }
            
            // Leave button
            Button(action: { viewModel.leaveRoom() }) {
                Text("Leave Room")
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.danger)
            }
        }
        .padding(24)
    }
    
    private var playersListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players (\(viewModel.gameState?.players.count ?? 0)/4)")
                .font(Typography.subtitle)
                .foregroundColor(ThemeColors.textPrimary)
            
            VStack(spacing: 8) {
                if let players = viewModel.gameState?.players {
                    ForEach(players) { player in
                        PlayerRowView(
                            player: player,
                            isLocalPlayer: player.id == viewModel.localPlayerId
                        )
                    }
                }
                
                // Empty slots
                let emptySlots = 4 - (viewModel.gameState?.players.count ?? 0)
                ForEach(0..<emptySlots, id: \.self) { _ in
                    EmptyPlayerSlotView()
                }
            }
        }
    }
    
    private var hostControls: some View {
        VStack(spacing: 12) {
            let playerCount = viewModel.gameState?.players.count ?? 0
            let allReady = viewModel.gameState?.players.allSatisfy { $0.status == .ready || $0.isHost } ?? false
            // Allow single player for testing, or 2+ players where all are ready
            let canStart = playerCount == 1 || (playerCount >= 2 && allReady)
            
            Button(action: { viewModel.startGame() }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                    Text(playerCount == 1 ? "Start Solo (Test)" : "Start Game")
                }
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: LayoutConstants.buttonHeight)
                .background(canStart ? ThemeColors.buttonGradient : LinearGradient(colors: [ThemeColors.cardBack], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
            }
            .disabled(!canStart)
            
            if !canStart && playerCount >= 2 {
                Text("Waiting for all players to be ready...")
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.textMuted)
            }
        }
    }
    
    private var guestControls: some View {
        VStack(spacing: 12) {
            let isReady = viewModel.localPlayer?.status == .ready
            
            Button(action: { viewModel.setReady(!isReady) }) {
                HStack(spacing: 12) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                    Text(isReady ? "Ready!" : "Ready Up")
                }
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(isReady ? ThemeColors.secondary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: LayoutConstants.buttonHeight)
                .background {
                    if isReady {
                        ThemeColors.secondary.opacity(0.2)
                    } else {
                        ThemeColors.buttonGradient
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius)
                        .stroke(isReady ? ThemeColors.secondary : Color.clear, lineWidth: 2)
                )
            }
            
            Text("Waiting for host to start...")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.textMuted)
        }
    }
    
    // MARK: - Connection Status
    
    private var connectionStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            
            Text(connectionText)
                .font(Typography.caption)
                .foregroundColor(ThemeColors.textMuted)
        }
        .padding(.bottom, 20)
    }
    
    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return ThemeColors.secondary
        case .connecting, .reconnecting:
            return ThemeColors.warning
        case .disconnected, .failed:
            return ThemeColors.danger
        }
    }
    
    private var connectionText: String {
        switch viewModel.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))..."
        case .disconnected:
            return "Disconnected"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        ZStack {
            ThemeColors.background
            
            // Decorative elements
            GeometryReader { geo in
                Circle()
                    .fill(ThemeColors.primary.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: -100, y: -50)
                
                Circle()
                    .fill(ThemeColors.secondary.opacity(0.1))
                    .frame(width: 250, height: 250)
                    .blur(radius: 80)
                    .offset(x: geo.size.width - 100, y: geo.size.height - 200)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Actions
    
    private func createRoom() {
        guard !playerName.isEmpty else { return }
        isConnecting = true
        viewModel.connect()
        
        // Wait for connection then create room
        waitForConnectionThen {
            viewModel.createRoom(playerName: playerName)
            isConnecting = false
        }
    }
    
    private func joinRoom() {
        guard !playerName.isEmpty, !roomCode.isEmpty else { return }
        isConnecting = true
        viewModel.connect()
        
        // Wait for connection then join room
        waitForConnectionThen {
            viewModel.joinRoom(code: roomCode, playerName: playerName)
            isConnecting = false
        }
    }
    
    private func waitForConnectionThen(action: @escaping () -> Void) {
        // Poll for connection state
        var attempts = 0
        let maxAttempts = 20 // 2 seconds max
        
        func checkConnection() {
            if viewModel.connectionState == .connected {
                action()
            } else if attempts < maxAttempts {
                attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkConnection()
                }
            } else {
                // Timeout
                isConnecting = false
                print("Connection timeout - could not connect to server")
            }
        }
        
        checkConnection()
    }
    
    private func copyRoomCode() {
        guard let code = viewModel.gameState?.roomCode else { return }
        UIPasteboard.general.string = code
        HapticFeedback.light()
    }
}

// MARK: - Player Row View

struct PlayerRowView: View {
    let player: Player
    let isLocalPlayer: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(ThemeColors.primary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(player.name.prefix(1)).uppercased())
                        .font(Typography.body)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeColors.primary)
                )
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textPrimary)
                    
                    if isLocalPlayer {
                        Text("(You)")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.textMuted)
                    }
                    
                    if player.isHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.warning)
                    }
                }
            }
            
            Spacer()
            
            // Status
            statusBadge
        }
        .padding(12)
        .background(ThemeColors.cardBack.opacity(isLocalPlayer ? 0.8 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch player.status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.secondary)
        case .waiting:
            Text("Waiting")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.textMuted)
        case .disconnected:
            Label("Offline", systemImage: "wifi.slash")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.danger)
        default:
            EmptyView()
        }
    }
}

struct EmptyPlayerSlotView: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(ThemeColors.textMuted.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 40, height: 40)
            
            Text("Waiting for player...")
                .font(Typography.body)
                .foregroundColor(ThemeColors.textMuted)
            
            Spacer()
        }
        .padding(12)
        .background(ThemeColors.cardBack.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview
#Preview {
    LobbyView(viewModel: GameViewModel())
}

