import Foundation

// MARK: - Card Suit
enum Suit: String, Codable, CaseIterable {
    case hearts
    case diamonds
    case clubs
    case spades
    case hidden  // For cards we can't see
    
    var symbol: String {
        switch self {
        case .hearts: return "heart.fill"
        case .diamonds: return "diamond.fill"
        case .clubs: return "suit.club.fill"
        case .spades: return "suit.spade.fill"
        case .hidden: return "questionmark"
        }
    }
    
    var isRed: Bool {
        self == .hearts || self == .diamonds
    }
    
    // Exclude hidden from CaseIterable for deck generation
    static var allCases: [Suit] {
        [.hearts, .diamonds, .clubs, .spades]
    }
}

// MARK: - Card Rank
enum Rank: String, Codable, CaseIterable, Comparable {
    case ace
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case ten
    case jack
    case queen
    case king
    case hidden  // For cards we can't see
    
    var numericValue: Int {
        switch self {
        case .ace: return 1
        case .two: return 2
        case .three: return 3
        case .four: return 4
        case .five: return 5
        case .six: return 6
        case .seven: return 7
        case .eight: return 8
        case .nine: return 9
        case .ten: return 10
        case .jack: return 11
        case .queen: return 12
        case .king: return 13
        case .hidden: return 0
        }
    }
    
    var displayValue: String {
        switch self {
        case .ace: return "A"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .hidden: return "?"
        default: return "\(numericValue)"
        }
    }
    
    var scoreValue: Int {
        switch self {
        case .jack, .queen, .king:
            return 10
        case .hidden:
            return 0
        default:
            return numericValue
        }
    }
    
    static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.numericValue < rhs.numericValue
    }
    
    // Exclude hidden from CaseIterable for deck generation
    static var allCases: [Rank] {
        [.ace, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king]
    }
}

// MARK: - Card Ability
enum CardAbility: Equatable {
    case peekOwn        // 7, 8 - Peek at one of your own cards
    case peekOther      // 9, 10 - Peek at opponent's card
    case swap           // J, Q - Swap cards between players
    case none           // All other cards
    
    var description: String {
        switch self {
        case .peekOwn: return "Peek at one of your own cards"
        case .peekOther: return "Peek at one opponent's card"
        case .swap: return "Swap a card with another player"
        case .none: return "No special ability"
        }
    }
}

// MARK: - Card
struct Card: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let suit: Suit
    let rank: Rank
    
    init(suit: Suit, rank: Rank) {
        self.id = UUID()
        self.suit = suit
        self.rank = rank
    }
    
    var ability: CardAbility {
        switch rank {
        case .seven, .eight:
            return .peekOwn
        case .nine, .ten:
            return .peekOther
        case .jack, .queen:
            return .swap
        default:
            return .none
        }
    }
    
    var displayName: String {
        "\(rank.displayValue) of \(suit.rawValue.capitalized)"
    }
    
    var shortName: String {
        "\(rank.displayValue)\(suit.symbol)"
    }
    
    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Deck
struct Deck {
    private(set) var cards: [Card] = []
    
    init() {
        reset()
    }
    
    mutating func reset() {
        cards = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(Card(suit: suit, rank: rank))
            }
        }
    }
    
    mutating func shuffle() {
        cards.shuffle()
    }
    
    mutating func setCards(_ newCards: [Card]) {
        cards = newCards
    }
    
    mutating func draw() -> Card? {
        guard !cards.isEmpty else { return nil }
        return cards.removeFirst()
    }
    
    mutating func drawMultiple(_ count: Int) -> [Card] {
        var drawn: [Card] = []
        for _ in 0..<count {
            if let card = draw() {
                drawn.append(card)
            }
        }
        return drawn
    }
    
    var isEmpty: Bool {
        cards.isEmpty
    }
    
    var count: Int {
        cards.count
    }
}

// MARK: - PlayerCard (card in player's hand)
struct PlayerCard: Identifiable, Codable, Equatable {
    let id: UUID
    var card: Card
    var isFaceUp: Bool
    var position: Int // 0-3 for the 4 card positions (0,1 top row, 2,3 bottom row)
    var isPeeked: Bool? // true if local player has seen this card
    
    init(card: Card, position: Int, isFaceUp: Bool = false, isPeeked: Bool = false) {
        self.id = UUID()
        self.card = card
        self.position = position
        self.isFaceUp = isFaceUp
        self.isPeeked = isPeeked
    }
}

