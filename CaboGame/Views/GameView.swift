import SwiftUI

// MARK: - Game View
struct GameView: View {
    @StateObject private var viewModel = GameViewModel()
    @EnvironmentObject var audioManager: AudioManager
    
    var body: some View {
        ZStack {
            // Background
            ThemeColors.background
                .ignoresSafeArea()
            
            // Main content based on phase
            Group {
                switch viewModel.currentPhase {
                case .lobby:
                    LobbyView(viewModel: viewModel)
                    
                case .initialPeek:
                    // Show auto-peeked cards and wait for player to confirm
                    initialPeekContent
                    
                case .playing, .finalRound, .reactionWindow:
                    gamePlayContent
                    
                case .scoring, .gameOver:
                    if let result = viewModel.showingGameResult {
                        GameResultView(result: result) {
                            viewModel.leaveRoom()
                        }
                    }
                }
            }
            
            // Music toggle button (top-left corner)
            VStack {
                HStack {
                    Button(action: { audioManager.toggleMusic() }) {
                        Image(systemName: audioManager.isMusicPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 16))
                            .foregroundColor(ThemeColors.textPrimary)
                            .padding(8)
                            .background(ThemeColors.cardTable.opacity(0.8))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 50)
                Spacer()
            }
            
            // Overlays
            overlayViews
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Initial Peek Content
    
    @ViewBuilder
    private var initialPeekContent: some View {
        if let player = viewModel.localPlayer,
           let gameState = viewModel.gameState {
            let readyCount = gameState.players.filter { $0.readyToPlay == true }.count
            let peekedSet = Set(player.peekedPositions ?? [])
            
            InitialPeekView(
                player: player,
                peeksRemaining: player.peeksRemaining,
                peekedPositions: peekedSet,
                isReady: player.readyToPlay == true,
                readyCount: readyCount,
                totalPlayers: gameState.players.count,
                onPeek: { _ in },  // No manual peeking - auto-peeked
                onFinish: {
                    viewModel.finishInitialPeek()
                }
            )
        }
    }
    
    // MARK: - Game Play Content
    
    @ViewBuilder
    private var gamePlayContent: some View {
        VStack(spacing: 0) {
            // Opponents area
            opponentsSection
            
            Spacer()
            
            // Center area (deck, discard, drawn card)
            centerPlayArea
            
            Spacer()
            
            // Local player area
            localPlayerSection
            
            // Action buttons
            actionButtonsSection
        }
        .padding(.vertical, LayoutConstants.padding)
    }
    
    // MARK: - Opponents Section
    
    @ViewBuilder
    private var opponentsSection: some View {
        let opponents = viewModel.opponents
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(opponents) { opponent in
                    OpponentHandView(
                        player: opponent,
                        isCurrentTurn: viewModel.gameState?.currentPlayerId == opponent.id,
                        selectedPlayerId: viewModel.selectedOpponentId,
                        selectedPosition: viewModel.selectedOpponentPosition,
                        onCardTap: { playerId, position in
                            handleOpponentCardTap(playerId: playerId, position: position)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: LayoutConstants.opponentAreaHeight)
    }
    
    // MARK: - Center Play Area
    
    @ViewBuilder
    private var centerPlayArea: some View {
        VStack(spacing: 20) {
            // Cabo indicator
            if viewModel.gameState?.isCaboActive == true {
                CaboIndicatorView(
                    callerName: viewModel.gameState?.player(withId: viewModel.gameState?.caboCallerId ?? UUID())?.name ?? ""
                )
            }
            
            // Turn indicator
            if viewModel.isMyTurn {
                TurnTimerView(timeRemaining: viewModel.turnTimeRemaining)
            } else if let currentPlayer = viewModel.gameState?.currentPlayer {
                // Show whose turn it is for other players
                WaitingIndicatorView(playerName: currentPlayer.name)
            }
            
            // Deck and Discard (auto-draw, no interaction)
            HStack(spacing: 40) {
                // Deck
                VStack(spacing: 8) {
                    DeckPileView(
                        count: viewModel.deckCount,
                        isInteractive: false,
                        onTap: nil
                    )
                    Text("Deck (\(viewModel.deckCount))")
                        .font(Typography.caption)
                        .foregroundColor(ThemeColors.textMuted)
                }
                
                // Discard
                VStack(spacing: 8) {
                    DiscardPileView(
                        topCard: viewModel.topDiscardCard,
                        isInteractive: false,
                        onTap: nil
                    )
                    Text("Discard")
                        .font(Typography.caption)
                        .foregroundColor(ThemeColors.textMuted)
                }
            }
        }
    }
    
    // MARK: - Local Player Section
    
    @ViewBuilder
    private var localPlayerSection: some View {
        if let player = viewModel.localPlayer {
            let canReactPositions = getReactablePositions()
            // Use pendingReplacePosition when in deciding phase, otherwise use selectedCardPosition
            let selectedPos = viewModel.pendingReplacePosition ?? viewModel.selectedCardPosition
            
            PlayerHandView(
                player: player,
                isLocalPlayer: true,
                isCurrentTurn: viewModel.isMyTurn,
                selectedPosition: selectedPos,
                canReact: canReactPositions,
                onCardTap: { position in
                    handleLocalCardTap(position: position)
                }
            )
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Only show action UI to the current player (their turn)
            if viewModel.isMyTurn {
                // Drawn card actions
                if let drawnCard = viewModel.drawnCard {
                    DrawnCardActionsView(
                        card: drawnCard,
                        pendingReplacePosition: viewModel.pendingReplacePosition,
                        onDiscard: { viewModel.discardDrawnCard() },
                        onConfirmReplace: { viewModel.confirmReplace() },
                        onCancelReplace: { viewModel.cancelReplace() }
                    )
                }
                
                // Ability actions (only current player sees this)
                if viewModel.gameState?.turnPhase == .usingAbility {
                    AbilityActionsView(
                        ability: viewModel.topDiscardCard?.ability ?? .none,
                        onUse: { viewModel.useAbility() },
                        onSkip: { viewModel.skipAbility() }
                    )
                }
                
                // Swap target selection (only current player sees this)
                if viewModel.gameState?.turnPhase == .selectingTarget,
                   viewModel.topDiscardCard?.ability == .swap {
                    SwapSelectionView(
                        hasSelectedOwnCard: viewModel.selectedCardPosition != nil,
                        hasSelectedOpponentCard: viewModel.selectedOpponentId != nil,
                        onConfirm: { viewModel.swapCards() },
                        onSkip: { viewModel.skipAbility() }
                    )
                }
                
                // Peek target selection guidance
                if viewModel.gameState?.turnPhase == .selectingTarget,
                   let ability = viewModel.topDiscardCard?.ability,
                   (ability == .peekOwn || ability == .peekOther) {
                    PeekSelectionView(
                        ability: ability,
                        onSkip: { viewModel.skipAbility() }
                    )
                }
                
                // Cabo button
                if viewModel.canCallCabo {
                    CaboButton(onCabo: { viewModel.callCabo() })
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    private var overlayViews: some View {
        // Card replace animation
        if let animation = viewModel.cardReplaceAnimation {
            CardReplaceAnimationView(animation: animation)
        }
        
        // Card discard animation
        if let animation = viewModel.cardDiscardAnimation {
            CardDiscardAnimationView(animation: animation)
        }
        
        // Card draw animation
        if let animation = viewModel.cardDrawAnimation {
            CardDrawAnimationView(animation: animation)
        }
        
        // Card swap animation (for local player)
        if let animation = viewModel.cardSwapAnimation {
            CardSwapAnimationView(animation: animation)
        }
        
        // Broadcast swap animation (for other players watching)
        if let animation = viewModel.broadcastSwapAnimation {
            BroadcastSwapAnimationView(animation: animation)
        }
        
        // Peek notification (when another player is peeking)
        if let notification = viewModel.peekNotification {
            VStack {
                HStack {
                    Spacer()
                    Text(notification)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.9))
                        )
                    Spacer()
                }
                .padding(.top, 100)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: viewModel.peekNotification)
                
                Spacer()
            }
        }
        
        // Reaction timer in top-right corner (non-blocking)
        if viewModel.isInReactionWindow {
            VStack {
                HStack {
                    Spacer()
                    ReactionBannerView(
                        timeRemaining: viewModel.reactionTimeRemaining,
                        matchRank: viewModel.topDiscardCard?.rank.displayValue
                    )
                    .padding(.trailing, 12)
                    .padding(.top, 50)
                }
                Spacer()
            }
        }
        
        // Peek card overlay
        if let card = viewModel.showingPeekCard {
            PeekCardOverlay(
                card: card,
                position: viewModel.peekCardPosition ?? 0,
                isOwnCard: viewModel.peekCardOwner == viewModel.localPlayerId,
                onDismiss: { viewModel.dismissPeek() }
            )
        }
        
        // Reaction alert
        if viewModel.showingReactionAlert {
            ReactionAlertOverlay(
                timeRemaining: viewModel.reactionTimeRemaining,
                topCard: viewModel.topDiscardCard,
                onReact: { position in
                    viewModel.reactWithCard(at: position)
                }
            )
        }
        
        // Error toast
        if let error = viewModel.errorMessage {
            ErrorToast(message: error) {
                viewModel.clearError()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleLocalCardTap(position: Int) {
        guard let gameState = viewModel.gameState else { return }
        
        // First check if we're in reaction window (highest priority)
        if viewModel.isInReactionWindow {
            viewModel.reactWithCard(at: position)
            return
        }
        
        // Then check turn phase for normal actions
        switch gameState.turnPhase {
        case .deciding:
            // Two-step replace: if tapping the same card, toggle off; otherwise select
            if viewModel.pendingReplacePosition == position {
                viewModel.cancelReplace()
            } else {
                viewModel.selectCardForReplace(at: position)
            }
            
        case .selectingTarget:
            if let topCard = viewModel.topDiscardCard {
                switch topCard.ability {
                case .peekOwn:
                    viewModel.peekOwnCard(at: position)
                case .swap:
                    viewModel.selectOwnCard(at: position)
                default:
                    break
                }
            }
            
        default:
            break
        }
    }
    
    private func handleOpponentCardTap(playerId: UUID, position: Int) {
        guard let gameState = viewModel.gameState else { return }
        
        switch gameState.turnPhase {
        case .selectingTarget:
            if let topCard = viewModel.topDiscardCard {
                switch topCard.ability {
                case .peekOther:
                    viewModel.peekOpponentCard(playerId: playerId, position: position)
                case .swap:
                    viewModel.selectOpponentCard(playerId: playerId, position: position)
                default:
                    break
                }
            }
            
        default:
            break
        }
    }
    
    private func getReactablePositions() -> Set<Int> {
        guard let player = viewModel.localPlayer,
              let gameState = viewModel.gameState else { return [] }
        
        // During reaction window, ALL cards are reactable (penalty for wrong guess)
        if viewModel.isInReactionWindow {
            return Set(0..<player.cards.count)
        }
        
        // During selectingTarget for peek/swap, highlight own cards
        if gameState.turnPhase == .selectingTarget && viewModel.isMyTurn {
            if let topCard = viewModel.topDiscardCard {
                if topCard.ability == .peekOwn || topCard.ability == .swap {
                    return Set(0..<player.cards.count)
                }
            }
        }
        
        return []
    }
}

// MARK: - Supporting Views

struct CaboIndicatorView: View {
    let callerName: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(ThemeColors.caboHighlight)
            
            Text("\(callerName) called CABO!")
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(ThemeColors.caboHighlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ThemeColors.caboHighlight.opacity(0.2))
        .clipShape(Capsule())
    }
}

struct TurnTimerView: View {
    let timeRemaining: TimeInterval
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .foregroundColor(timerColor)
            
            Text(String(format: "%.0f", timeRemaining))
                .font(Typography.timer)
                .foregroundColor(timerColor)
                .monospacedDigit()
        }
    }
    
    private var timerColor: Color {
        if timeRemaining < 10 {
            return ThemeColors.danger
        } else if timeRemaining < 30 {
            return ThemeColors.warning
        }
        return ThemeColors.textPrimary
    }
}

struct WaitingIndicatorView: View {
    let playerName: String
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: ThemeColors.textSecondary))
                .scaleEffect(0.8)
            
            Text("\(playerName)'s turn")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ThemeColors.cardBack.opacity(0.8))
        .clipShape(Capsule())
    }
}

struct ReactionTimerView: View {
    let timeRemaining: TimeInterval
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundColor(ThemeColors.reactionWindow)
            
            Text(String(format: "%.1fs", timeRemaining))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeColors.reactionWindow)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ThemeColors.reactionWindow.opacity(0.25))
        .clipShape(Capsule())
    }
}

struct ReactionBannerView: View {
    let timeRemaining: TimeInterval
    let matchRank: String?
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                Text(String(format: "%.1fs", timeRemaining))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .foregroundColor(ThemeColors.reactionWindow)
            
            if let rank = matchRank {
                Text("Match: \(rank)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ThemeColors.background.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ThemeColors.reactionWindow.opacity(0.5), lineWidth: 1)
        )
    }
}

struct DrawnCardActionsView: View {
    let card: Card
    let pendingReplacePosition: Int?
    let onDiscard: () -> Void
    let onConfirmReplace: () -> Void
    let onCancelReplace: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CardView(card: card, isFaceUp: true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drawn: \(card.displayName)")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textPrimary)
                    
                    if pendingReplacePosition != nil {
                        Text("Card \(pendingReplacePosition! + 1) selected")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.primary)
                    } else {
                        Text("Tap a card to replace it")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
            }
            
            if let _ = pendingReplacePosition {
                // Two-step: show confirm/cancel buttons
                HStack(spacing: 12) {
                    Button(action: onCancelReplace) {
                        Text("Undo")
                            .font(Typography.body)
                            .foregroundColor(ThemeColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(ThemeColors.cardBack)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button(action: onConfirmReplace) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(ThemeColors.buttonGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                // Show discard button
                Button(action: onDiscard) {
                    Label("Discard", systemImage: "arrow.down.doc")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ThemeColors.cardBack)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(ThemeColors.cardTable)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AbilityActionsView: View {
    let ability: CardAbility
    let onUse: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text(ability.description)
                .font(Typography.body)
                .foregroundColor(ThemeColors.textPrimary)
            
            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ThemeColors.cardBack)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Button(action: onUse) {
                    Text("Use Ability")
                        .font(Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ThemeColors.buttonGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(ThemeColors.cardTable)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SwapSelectionView: View {
    let hasSelectedOwnCard: Bool
    let hasSelectedOpponentCard: Bool
    let onConfirm: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Instructions
            VStack(spacing: 4) {
                Text("SWAP ABILITY")
                    .font(Typography.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ThemeColors.primary)
                
                if !hasSelectedOwnCard {
                    Text("Tap one of YOUR cards")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                } else if !hasSelectedOpponentCard {
                    Text("Tap an OPPONENT's card")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                } else {
                    Text("Ready to swap!")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.secondary)
                }
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ThemeColors.cardBack)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                if hasSelectedOwnCard && hasSelectedOpponentCard {
                    Button(action: onConfirm) {
                        Label("Confirm Swap", systemImage: "arrow.left.arrow.right")
                            .font(Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(ThemeColors.buttonGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .background(ThemeColors.cardTable)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PeekSelectionView: View {
    let ability: CardAbility
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(ability == .peekOwn ? "PEEK YOUR CARD" : "PEEK OPPONENT'S CARD")
                    .font(Typography.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ThemeColors.primary)
                
                Text(ability == .peekOwn ? "Tap one of your cards to peek" : "Tap an opponent's card to peek")
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textSecondary)
            }
            
            Button(action: onSkip) {
                Text("Skip")
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(ThemeColors.cardBack)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(ThemeColors.cardTable)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SwapConfirmButton: View {
    let onConfirm: () -> Void
    
    var body: some View {
        Button(action: onConfirm) {
            Label("Confirm Swap", systemImage: "arrow.left.arrow.right")
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: LayoutConstants.buttonHeight)
                .background(ThemeColors.buttonGradient)
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
        }
    }
}

struct CaboButton: View {
    let onCabo: () -> Void
    
    var body: some View {
        Button(action: onCabo) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                Text("CABO")
                    .fontWeight(.heavy)
            }
            .font(Typography.subtitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: LayoutConstants.buttonHeight)
            .background(ThemeColors.dangerGradient)
            .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
        }
    }
}

struct PeekCardOverlay: View {
    let card: Card
    let position: Int
    let isOwnCard: Bool
    let onDismiss: () -> Void
    
    @State private var showCard = false
    @State private var cardScale: CGFloat = 0.3
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            
            VStack(spacing: 16) {
                // Header with icon
                VStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 36))
                        .foregroundColor(ThemeColors.secondary)
                    Text("MEMORIZE THIS!")
                        .font(Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeColors.secondary)
                }
                .opacity(showCard ? 1 : 0)
                
                // Card info
                Text(isOwnCard ? "Your Card" : "Opponent's Card")
                    .font(Typography.subtitle)
                    .foregroundColor(ThemeColors.textPrimary)
                    .opacity(showCard ? 1 : 0)
                
                // Card with flip animation
                CardView(card: card, isFaceUp: showCard)
                    .scaleEffect(cardScale)
                
                // Position indicator
                Text(positionLabel)
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textSecondary)
                    .opacity(showCard ? 1 : 0)
                
                // Reminder text
                Text("Card will be hidden after closing")
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.warning)
                    .opacity(showCard ? 1 : 0)
                
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("I'll Remember")
                    }
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(ThemeColors.buttonGradient)
                    .clipShape(Capsule())
                }
                .opacity(showCard ? 1 : 0)
            }
        }
        .onAppear {
            // Animate card reveal
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                cardScale = 1.8
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                showCard = true
            }
        }
    }
    
    private var positionLabel: String {
        let row = position < 2 ? "Top" : "Bottom"
        let col = position % 2 == 0 ? "Left" : "Right"
        return "\(row) \(col)"
    }
}

struct ReactionAlertOverlay: View {
    let timeRemaining: TimeInterval
    let topCard: Card?
    let onReact: (Int) -> Void
    
    var body: some View {
        // Empty - we now use ReactionTimerView in corner instead
        EmptyView()
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(ThemeColors.danger)
                
                Text(message)
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textPrimary)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(ThemeColors.textMuted)
                }
            }
            .padding()
            .background(ThemeColors.cardBack)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                onDismiss()
            }
        }
    }
}

struct GameResultView: View {
    let result: GameResult
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Game Over")
                    .font(Typography.title)
                    .foregroundColor(ThemeColors.textPrimary)
                
                Text("\(result.winnerName) wins!")
                    .font(Typography.subtitle)
                    .foregroundColor(ThemeColors.secondary)
            }
            
            // Scores
            VStack(spacing: 12) {
                let sortedScores = result.scores.sorted { $0.score < $1.score }
                
                ForEach(sortedScores.indices, id: \.self) { index in
                    ScoreCardView(
                        playerScore: sortedScores[index],
                        isWinner: sortedScores[index].playerId == result.winnerId,
                        rank: index + 1
                    )
                }
            }
            
            // Cabo result
            if let caller = result.scores.first(where: { $0.calledCabo }) {
                HStack(spacing: 8) {
                    Image(systemName: result.wasCaboSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.wasCaboSuccessful ? ThemeColors.secondary : ThemeColors.danger)
                    
                    Text(result.wasCaboSuccessful ? "Cabo succeeded!" : "Cabo failed!")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                }
            }
            
            // Play again button
            Button(action: onDismiss) {
                Text("Back to Lobby")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: LayoutConstants.buttonHeight)
                    .background(ThemeColors.buttonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
            }
        }
        .padding(24)
        .background(ThemeColors.cardTable)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding()
    }
}

// MARK: - Card Replace Animation View
struct CardReplaceAnimationView: View {
    let animation: CardReplaceAnimation
    
    @State private var drawnCardOffset: CGSize = .zero
    @State private var replacedCardOffset: CGSize = .zero
    @State private var drawnCardOpacity: Double = 1.0
    @State private var replacedCardOpacity: Double = 1.0
    @State private var showAnimation = false
    
    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let handY = geometry.size.height - 150  // Approximate hand position
            let discardY = screenCenter.y
            
            // Calculate target position based on card position (2x2 grid)
            let targetX = cardTargetX(for: animation.targetPosition, screenWidth: geometry.size.width)
            let targetY = cardTargetY(for: animation.targetPosition, baseY: handY)
            
            ZStack {
                // Semi-transparent background
                Color.black.opacity(showAnimation ? 0.3 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                
                // Drawn card moving to hand (always face up - player knows this card)
                CardView(card: animation.drawnCard, isFaceUp: true)
                    .scaleEffect(0.9)
                    .position(x: screenCenter.x, y: discardY - 60)
                    .offset(drawnCardOffset)
                    .opacity(drawnCardOpacity)
                
                // Replaced card moving to discard
                // Show face up only if we know the card (not hidden), otherwise show card back
                let isKnownCard = animation.replacedCard.rank != .hidden
                let _ = print("[Animation] replacedCard rank=\(animation.replacedCard.rank.displayValue), isKnownCard=\(isKnownCard)")
                CardView(card: animation.replacedCard, isFaceUp: isKnownCard)
                    .scaleEffect(0.9)
                    .position(x: targetX, y: targetY)
                    .offset(replacedCardOffset)
                    .opacity(replacedCardOpacity)
            }
            .onAppear {
                // Calculate offsets
                let drawnTargetOffset = CGSize(
                    width: targetX - screenCenter.x,
                    height: targetY - (discardY - 60)
                )
                let replacedTargetOffset = CGSize(
                    width: screenCenter.x - targetX,
                    height: discardY - targetY
                )
                
                withAnimation(.easeIn(duration: 0.3)) {
                    showAnimation = true
                }
                
                // Animate drawn card to hand position (much slower - 1.5s)
                withAnimation(.easeInOut(duration: 1.5).delay(0.3)) {
                    drawnCardOffset = drawnTargetOffset
                }
                
                // Animate replaced card to discard (much slower - 1.5s)
                withAnimation(.easeInOut(duration: 1.5).delay(0.3)) {
                    replacedCardOffset = replacedTargetOffset
                }
                
                // Fade out after movement completes
                withAnimation(.easeOut(duration: 0.4).delay(2.0)) {
                    drawnCardOpacity = 0
                    replacedCardOpacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func cardTargetX(for position: Int, screenWidth: CGFloat) -> CGFloat {
        let centerX = screenWidth / 2
        let cardSpacing: CGFloat = 60
        
        // 2x2 grid: positions 0,1 top row, 2,3 bottom row
        let isLeftColumn = position % 2 == 0
        return isLeftColumn ? centerX - cardSpacing/2 - 25 : centerX + cardSpacing/2 + 25
    }
    
    private func cardTargetY(for position: Int, baseY: CGFloat) -> CGFloat {
        let rowSpacing: CGFloat = 80
        let isTopRow = position < 2
        return isTopRow ? baseY - rowSpacing : baseY
    }
}

// MARK: - Card Swap Animation View
struct CardSwapAnimationView: View {
    let animation: CardSwapAnimation
    
    @State private var myCardOffset: CGSize = .zero
    @State private var opponentCardOffset: CGSize = .zero
    @State private var showAnimation = false
    @State private var cardsOpacity: Double = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let myHandY = geometry.size.height - 150
            let opponentY: CGFloat = 120
            
            ZStack {
                // Semi-transparent background
                Color.black.opacity(showAnimation ? 0.4 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                
                // Label
                if showAnimation {
                    VStack {
                        Text("SWAP")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(ThemeColors.primary)
                        Text("with \(animation.opponentName)")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.textMuted)
                    }
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .opacity(cardsOpacity)
                }
                
                // My card moving up to opponent
                let isKnownMyCard = animation.myCard.rank != .hidden
                CardView(card: animation.myCard, isFaceUp: isKnownMyCard)
                    .scaleEffect(0.8)
                    .position(x: screenCenter.x - 40, y: myHandY)
                    .offset(myCardOffset)
                    .opacity(cardsOpacity)
                
                // Opponent card moving down to me
                CardView(card: animation.opponentCard, isFaceUp: false)  // Opponent card always face down
                    .scaleEffect(0.8)
                    .position(x: screenCenter.x + 40, y: opponentY)
                    .offset(opponentCardOffset)
                    .opacity(cardsOpacity)
            }
            .onAppear {
                let verticalDistance = myHandY - opponentY
                
                withAnimation(.easeIn(duration: 0.2)) {
                    showAnimation = true
                }
                
                // My card moves up
                withAnimation(.easeInOut(duration: 1.2).delay(0.2)) {
                    myCardOffset = CGSize(width: 40, height: -verticalDistance)
                }
                
                // Opponent card moves down
                withAnimation(.easeInOut(duration: 1.2).delay(0.2)) {
                    opponentCardOffset = CGSize(width: -40, height: verticalDistance)
                }
                
                // Fade out
                withAnimation(.easeOut(duration: 0.4).delay(1.5)) {
                    cardsOpacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Broadcast Swap Animation View (for other players watching)
struct BroadcastSwapAnimationView: View {
    let animation: SwapEventAnimation
    
    @State private var showAnimation = false
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(showAnimation ? 0.5 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            if showAnimation {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(ThemeColors.primary)
                    
                    Text("SWAP")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(animation.swapperName)
                            .fontWeight(.bold)
                            .foregroundColor(ThemeColors.primary)
                        Text("swapped with")
                            .foregroundColor(ThemeColors.textMuted)
                        Text(animation.opponentName)
                            .fontWeight(.bold)
                            .foregroundColor(ThemeColors.accent)
                    }
                    .font(.system(size: 16))
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(ThemeColors.primary.opacity(0.5), lineWidth: 2)
                        )
                )
                .opacity(opacity)
                .scaleEffect(showAnimation ? 1.0 : 0.5)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showAnimation = true
                opacity = 1.0
            }
            
            // Fade out after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Card Draw Animation View
struct CardDrawAnimationView: View {
    let animation: CardDrawAnimation
    
    @State private var cardOffset: CGSize = CGSize(width: -80, height: 0)
    @State private var cardOpacity: Double = 0.0
    @State private var cardScale: CGFloat = 0.8
    @State private var cardRotation: Double = -15
    
    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Card emerging from deck and moving to drawn position
                CardView(card: animation.card, isFaceUp: true)
                    .scaleEffect(cardScale)
                    .rotationEffect(.degrees(cardRotation))
                    .position(x: screenCenter.x, y: screenCenter.y - 60)
                    .offset(cardOffset)
                    .opacity(cardOpacity)
            }
            .onAppear {
                // Fade in and move from deck area
                withAnimation(.easeOut(duration: 0.3)) {
                    cardOpacity = 1.0
                }
                
                // Animate card sliding from deck to center
                withAnimation(.easeInOut(duration: 0.8)) {
                    cardOffset = .zero
                    cardScale = 1.0
                    cardRotation = 0
                }
                
                // Fade out
                withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
                    cardOpacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Card Discard Animation View
struct CardDiscardAnimationView: View {
    let animation: CardDiscardAnimation
    
    @State private var cardOffset: CGSize = CGSize(width: 0, height: -60)
    @State private var cardOpacity: Double = 1.0
    @State private var cardScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Card moving down to discard pile
                CardView(card: animation.card, isFaceUp: true)
                    .scaleEffect(cardScale)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .offset(cardOffset)
                    .opacity(cardOpacity)
            }
            .onAppear {
                // Animate card dropping into discard pile (slower - 1.0s)
                withAnimation(.easeInOut(duration: 1.0)) {
                    cardOffset = .zero
                    cardScale = 0.95
                }
                
                // Fade out after movement
                withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
                    cardOpacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Preview
#Preview {
    GameView()
        .environmentObject(AudioManager.shared)
}

