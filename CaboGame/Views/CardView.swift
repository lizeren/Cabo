import SwiftUI

// MARK: - Card View
struct CardView: View {
    let card: Card?
    let isFaceUp: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let isPeeked: Bool
    let onTap: (() -> Void)?
    
    init(
        card: Card?,
        isFaceUp: Bool = false,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        isPeeked: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.card = card
        self.isFaceUp = isFaceUp
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.isPeeked = isPeeked
        self.onTap = onTap
    }
    
    var body: some View {
        ZStack {
            if isFaceUp, let card = card {
                CardFrontView(card: card)
            } else {
                CardBackView()
            }
        }
        .frame(width: LayoutConstants.cardWidth, height: LayoutConstants.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius))
        .shadow(
            color: shadowColor,
            radius: isSelected ? 8 : 4,
            x: 0,
            y: isSelected ? 4 : 2
        )
        .overlay(selectionOverlay)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: AnimationDurations.cardFlip), value: isFaceUp)
        .onTapGesture {
            onTap?()
        }
    }
    
    private var shadowColor: Color {
        if isHighlighted {
            return ThemeColors.reactionWindow.opacity(0.6)
        } else if isSelected {
            return ThemeColors.primary.opacity(0.5)
        }
        return Color.black.opacity(0.3)
    }
    
    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .stroke(ThemeColors.primary, lineWidth: 3)
        } else if isHighlighted {
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .stroke(ThemeColors.reactionWindow, lineWidth: 2)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isHighlighted)
        }
    }
}

// MARK: - Card Front View
struct CardFrontView: View {
    let card: Card
    
    private var textColor: Color {
        card.suit.isRed ? ThemeColors.cardRed : ThemeColors.cardBlack
    }
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .fill(ThemeColors.cardFace)
            
            // Simple centered layout for small cards
            VStack(spacing: 2) {
                Text(card.rank.displayValue)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(textColor)
                
                Image(systemName: card.suit.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(textColor)
            }
        }
    }
}

// MARK: - Card Back View
struct CardBackView: View {
    var body: some View {
        ZStack {
            // Base
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .fill(ThemeColors.cardGradient)
            
            // Pattern
            GeometricPatternView()
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius - 2))
                .padding(4)
            
            // Border
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Geometric Pattern View
struct GeometricPatternView: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 12
            let dotSize: CGFloat = 3
            
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(ThemeColors.primary.opacity(0.15))
                    )
                }
            }
        }
    }
}

// MARK: - Deck Pile View
struct DeckPileView: View {
    let count: Int
    let isInteractive: Bool
    let onTap: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Stacked cards effect
            ForEach(0..<min(3, count), id: \.self) { index in
                CardBackView()
                    .frame(width: LayoutConstants.cardWidth, height: LayoutConstants.cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius))
                    .offset(x: CGFloat(index) * -2, y: CGFloat(index) * -2)
            }
            
            // Count badge
            if count > 0 {
                Text("\(count)")
                    .font(Typography.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ThemeColors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ThemeColors.primary.opacity(0.9))
                    .clipShape(Capsule())
                    .offset(y: -LayoutConstants.cardHeight / 2 - 10)
            }
        }
        .opacity(count > 0 ? 1 : 0.3)
        .scaleEffect(isInteractive ? 1.0 : 0.95)
        .animation(.spring(response: 0.3), value: isInteractive)
        .onTapGesture {
            guard isInteractive && count > 0 else { return }
            onTap?()
        }
    }
}

// MARK: - Discard Pile View
struct DiscardPileView: View {
    let topCard: Card?
    let isInteractive: Bool
    let onTap: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Empty pile indicator
            RoundedRectangle(cornerRadius: LayoutConstants.cardCornerRadius)
                .strokeBorder(
                    ThemeColors.textMuted.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .frame(width: LayoutConstants.cardWidth, height: LayoutConstants.cardHeight)
            
            // Top card
            if let card = topCard {
                CardView(
                    card: card,
                    isFaceUp: true,
                    isHighlighted: isInteractive,
                    onTap: onTap
                )
            }
        }
    }
}

// MARK: - Drawn Card View
struct DrawnCardView: View {
    let card: Card
    let onReplace: (Int) -> Void
    let onDiscard: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Drawn Card")
                .font(Typography.subtitle)
                .foregroundColor(ThemeColors.textSecondary)
            
            CardView(card: card, isFaceUp: true)
            
            Text("Tap a card to replace or discard")
                .font(Typography.caption)
                .foregroundColor(ThemeColors.textMuted)
            
            Button(action: onDiscard) {
                Text("Discard")
                    .font(Typography.body)
                    .foregroundColor(ThemeColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(ThemeColors.cardBack)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(ThemeColors.cardTable.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        ThemeColors.background.ignoresSafeArea()
        
        HStack(spacing: 20) {
            CardView(
                card: Card(suit: .hearts, rank: .ace),
                isFaceUp: true
            )
            
            CardView(
                card: Card(suit: .spades, rank: .king),
                isFaceUp: true,
                isSelected: true
            )
            
            CardView(
                card: nil,
                isFaceUp: false
            )
            
            CardView(
                card: nil,
                isFaceUp: false,
                isHighlighted: true
            )
        }
    }
}

