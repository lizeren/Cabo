import SwiftUI

// MARK: - Player Hand View
struct PlayerHandView: View {
    let player: Player
    let isLocalPlayer: Bool
    let isCurrentTurn: Bool
    let selectedPosition: Int?
    let canReact: Set<Int>
    let onCardTap: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Player name with status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(player.name)
                    .font(Typography.subtitle)
                    .foregroundColor(ThemeColors.textPrimary)
                
                if player.hasCalledCabo {
                    Text("CABO")
                        .font(Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeColors.caboHighlight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(ThemeColors.caboHighlight.opacity(0.2))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if isCurrentTurn {
                    Text("YOUR TURN")
                        .font(Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeColors.activePlayer)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                        .background(ThemeColors.activePlayer.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            
            // Cards in 2x2 grid layout (top row: 0,1 | bottom row: 2,3)
            // Bottom row cards (2,3) are the ones player peeks at start
            VStack(spacing: LayoutConstants.cardSpacing) {
                // Top row (positions 0, 1) - hidden at start
                HStack(spacing: LayoutConstants.cardSpacing) {
                    ForEach([0, 1], id: \.self) { position in
                        if position < player.cards.count {
                            cardView(for: position)
                        }
                    }
                }
                
                // Bottom row (positions 2, 3) - player sees these at start
                HStack(spacing: LayoutConstants.cardSpacing) {
                    ForEach([2, 3], id: \.self) { position in
                        if position < player.cards.count {
                            cardView(for: position)
                        }
                    }
                }
                
                // Extra cards from penalties (positions 4+)
                if player.cards.count > 4 {
                    HStack(spacing: LayoutConstants.cardSpacing) {
                        ForEach(4..<player.cards.count, id: \.self) { position in
                            cardView(for: position)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isCurrentTurn ? ThemeColors.activePlayer.opacity(0.1) : Color.clear)
        )
    }
    
    @ViewBuilder
    private func cardView(for position: Int) -> some View {
        let playerCard = player.cards[position]
        let canReactAtPosition = canReact.contains(position)
        // Only show card face-up if it's actually face up (revealed to all)
        // Peeked cards remain face-down with eye icon (player relies on memory)
        let shouldShowCard = playerCard.isFaceUp
        let hasPeeked = isLocalPlayer && playerCard.isPeeked == true
        
        CardView(
            card: playerCard.card,
            isFaceUp: shouldShowCard,
            isSelected: selectedPosition == position,
            isHighlighted: canReactAtPosition,
            isPeeked: hasPeeked && !playerCard.isFaceUp  // Show eye icon for memorized cards
        ) {
            onCardTap(position)
        }
    }
    
    private var statusColor: Color {
        switch player.status {
        case .playing:
            return isCurrentTurn ? ThemeColors.activePlayer : ThemeColors.secondary
        case .ready:
            return ThemeColors.secondary
        case .waiting:
            return ThemeColors.warning
        case .disconnected:
            return ThemeColors.danger
        case .spectating:
            return ThemeColors.textMuted
        }
    }
}

// MARK: - Opponent Hand View (Smaller, horizontal layout for opponents)
struct OpponentHandView: View {
    let player: Player
    let isCurrentTurn: Bool
    let selectedPlayerId: UUID?
    let selectedPosition: Int?
    let onCardTap: (UUID, Int) -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            // Player name
            HStack(spacing: 6) {
                Circle()
                    .fill(isCurrentTurn ? ThemeColors.activePlayer : ThemeColors.secondary)
                    .frame(width: 8, height: 8)
                
                Text(player.name)
                    .font(Typography.caption)
                    .foregroundColor(ThemeColors.textPrimary)
                    .lineLimit(1)
                
                if player.hasCalledCabo {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ThemeColors.caboHighlight)
                }
            }
            
            // Small cards in 2x2 grid
            VStack(spacing: 3) {
                // Top row (positions 0, 1)
                HStack(spacing: 3) {
                    ForEach([0, 1], id: \.self) { position in
                        if position < player.cards.count {
                            let playerCard = player.cards[position]
                            let isSelected = selectedPlayerId == player.id && selectedPosition == position
                            
                            SmallCardView(
                                card: playerCard.card,
                                isFaceUp: playerCard.isFaceUp,
                                isSelected: isSelected
                            ) {
                                onCardTap(player.id, position)
                            }
                        }
                    }
                }
                // Bottom row (positions 2, 3)
                HStack(spacing: 3) {
                    ForEach([2, 3], id: \.self) { position in
                        if position < player.cards.count {
                            let playerCard = player.cards[position]
                            let isSelected = selectedPlayerId == player.id && selectedPosition == position
                            
                            SmallCardView(
                                card: playerCard.card,
                                isFaceUp: playerCard.isFaceUp,
                                isSelected: isSelected
                            ) {
                                onCardTap(player.id, position)
                            }
                        }
                    }
                }
                // Extra cards row (positions 4+, for penalty cards)
                if player.cards.count > 4 {
                    HStack(spacing: 3) {
                        ForEach(4..<player.cards.count, id: \.self) { position in
                            let playerCard = player.cards[position]
                            let isSelected = selectedPlayerId == player.id && selectedPosition == position
                            
                            SmallCardView(
                                card: playerCard.card,
                                isFaceUp: playerCard.isFaceUp,
                                isSelected: isSelected
                            ) {
                                onCardTap(player.id, position)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentTurn ? ThemeColors.activePlayer.opacity(0.15) : ThemeColors.cardBack.opacity(0.5))
        )
    }
}

// MARK: - Small Card View (for opponents)
struct SmallCardView: View {
    let card: Card
    let isFaceUp: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    private let width: CGFloat = 36
    private let height: CGFloat = 50
    
    var body: some View {
        Group {
            if isFaceUp {
                SmallCardFrontView(card: card)
            } else {
                SmallCardBackView()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? ThemeColors.primary : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
        .onTapGesture(perform: onTap)
    }
}

struct SmallCardFrontView: View {
    let card: Card
    
    private var textColor: Color {
        card.suit.isRed ? ThemeColors.cardRed : ThemeColors.cardBlack
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(ThemeColors.cardFace)
            
            VStack(spacing: -1) {
                Text(card.rank.displayValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                
                Image(systemName: card.suit.symbol)
                    .font(.system(size: 9))
                    .foregroundColor(textColor)
            }
        }
    }
}

struct SmallCardBackView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(ThemeColors.cardGradient)
            
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(ThemeColors.primary.opacity(0.2), lineWidth: 1)
                .padding(3)
        }
    }
}

// MARK: - Initial Peek View
struct InitialPeekView: View {
    let player: Player
    let peeksRemaining: Int
    let peekedPositions: Set<Int>
    let isReady: Bool
    let readyCount: Int
    let totalPlayers: Int
    let onPeek: (Int) -> Void
    let onFinish: () -> Void
    
    @State private var showCards = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 40))
                    .foregroundColor(ThemeColors.secondary)
                
                Text("Memorize Your Cards")
                    .font(Typography.title)
                    .foregroundColor(ThemeColors.textPrimary)
                
                if isReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ThemeColors.primary))
                        Text("Waiting for others... (\(readyCount)/\(totalPlayers))")
                            .font(Typography.body)
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                } else {
                    Text("You can see your bottom 2 cards")
                        .font(Typography.body)
                        .foregroundColor(ThemeColors.textSecondary)
                }
            }
            
            // Cards in 2x2 grid layout
            VStack(spacing: LayoutConstants.cardSpacing) {
                // Top row - hidden (positions 0, 1)
                HStack(spacing: LayoutConstants.cardSpacing) {
                    ForEach([0, 1], id: \.self) { position in
                        if position < player.cards.count {
                            VStack(spacing: 4) {
                                CardView(card: nil, isFaceUp: false)
                                    .opacity(showCards ? 1 : 0)
                                Text("?")
                                    .font(Typography.caption)
                                    .foregroundColor(ThemeColors.textMuted)
                            }
                        }
                    }
                }
                
                // Bottom row - visible (positions 2, 3)
                HStack(spacing: LayoutConstants.cardSpacing) {
                    ForEach([2, 3], id: \.self) { position in
                        if position < player.cards.count {
                            let card = player.cards[position]
                            VStack(spacing: 4) {
                                CardView(
                                    card: card.card,
                                    isFaceUp: showCards,
                                    isPeeked: true
                                )
                                Text(positionLabel(position))
                                    .font(Typography.caption)
                                    .foregroundColor(ThemeColors.secondary)
                            }
                        }
                    }
                }
            }
            
            // Ready button
            if !isReady {
                Button(action: onFinish) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("I've Memorized My Cards")
                    }
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: LayoutConstants.buttonHeight)
                    .background(ThemeColors.buttonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.buttonCornerRadius))
                }
                .padding(.horizontal, 40)
            }
        }
        .padding()
        .onAppear {
            // Animate cards appearing
            withAnimation(.easeOut(duration: 0.5)) {
                showCards = true
            }
        }
    }
    
    private func positionLabel(_ position: Int) -> String {
        switch position {
        case 2: return "Left"
        case 3: return "Right"
        default: return ""
        }
    }
}

// MARK: - Score Card View
struct ScoreCardView: View {
    let playerScore: GameResult.PlayerScore
    let isWinner: Bool
    let rank: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("#\(rank)")
                .font(Typography.title)
                .foregroundColor(isWinner ? ThemeColors.secondary : ThemeColors.textMuted)
                .frame(width: 50)
            
            // Player info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(playerScore.playerName)
                        .font(Typography.subtitle)
                        .foregroundColor(ThemeColors.textPrimary)
                    
                    if playerScore.calledCabo {
                        Text("CABO")
                            .font(Typography.caption)
                            .foregroundColor(ThemeColors.caboHighlight)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ThemeColors.caboHighlight.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                // Cards
                HStack(spacing: 4) {
                    ForEach(playerScore.cards.indices, id: \.self) { index in
                        Text(playerScore.cards[index].rank.displayValue)
                            .font(Typography.cardSmall)
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // Score
            Text("\(playerScore.score)")
                .font(Typography.timer)
                .foregroundColor(isWinner ? ThemeColors.secondary : ThemeColors.textPrimary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isWinner ? ThemeColors.secondary.opacity(0.15) : ThemeColors.cardBack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWinner ? ThemeColors.secondary : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        ThemeColors.background.ignoresSafeArea()
        
        VStack(spacing: 20) {
            PlayerHandView(
                player: Player(name: "You"),
                isLocalPlayer: true,
                isCurrentTurn: true,
                selectedPosition: 1,
                canReact: [2],
                onCardTap: { _ in }
            )
            
            HStack(spacing: 16) {
                OpponentHandView(
                    player: Player(name: "Alice"),
                    isCurrentTurn: false,
                    selectedPlayerId: nil,
                    selectedPosition: nil,
                    onCardTap: { _, _ in }
                )
                
                OpponentHandView(
                    player: Player(name: "Bob"),
                    isCurrentTurn: true,
                    selectedPlayerId: nil,
                    selectedPosition: nil,
                    onCardTap: { _, _ in }
                )
            }
        }
        .padding()
    }
}

