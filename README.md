# Cabo Card Game

A multiplayer iOS card game inspired by Cabo, built with SwiftUI and WebSocket networking.

## Game Overview

- **Platform**: iOS (iPhone only, portrait orientation)
- **Players**: 2-4 human players
- **Game Type**: Turn-based, real-time multiplayer with reaction mechanics
- **Theme**: Minimalist, modern card game aesthetic

## Screenshots

The game features a dark, modern UI with:
- Elegant card designs with geometric patterns
- Glowing selection indicators
- Real-time countdown timers
- Smooth animations for card interactions

## Quick Start

### 1. Start the Server

```bash
cd Server
npm install
npm start
```

The server runs on `ws://localhost:8080/ws`

### 2. Build the iOS App

1. Open the project in Xcode 15+
2. Select an iPhone simulator or device
3. Build and run (Cmd+R)

### 3. Play!

1. Enter your name
2. Create a room (generates 6-character code)
3. Share code with friends
4. Wait for players and start!

## Project Structure

```
cabo/
©À©¤©¤ CaboGame/
©¦   ©À©¤©¤ Models/           # Data models
©¦   ©¦   ©À©¤©¤ Card.swift
©¦   ©¦   ©À©¤©¤ Player.swift
©¦   ©¦   ©À©¤©¤ GameState.swift
©¦   ©¦   ©¸©¤©¤ GameAction.swift
©¦   ©À©¤©¤ Engine/           # Game logic
©¦   ©¦   ©À©¤©¤ GameEngine.swift
©¦   ©¦   ©¸©¤©¤ TurnStateMachine.swift
©¦   ©À©¤©¤ Networking/       # Multiplayer
©¦   ©¦   ©À©¤©¤ WebSocketManager.swift
©¦   ©¦   ©À©¤©¤ GameRoom.swift
©¦   ©¦   ©¸©¤©¤ NetworkMessage.swift
©¦   ©À©¤©¤ ViewModels/       # MVVM
©¦   ©¦   ©¸©¤©¤ GameViewModel.swift
©¦   ©À©¤©¤ Views/            # SwiftUI
©¦   ©¦   ©À©¤©¤ GameView.swift
©¦   ©¦   ©À©¤©¤ LobbyView.swift
©¦   ©¦   ©À©¤©¤ CardView.swift
©¦   ©¦   ©¸©¤©¤ PlayerHandView.swift
©¦   ©¸©¤©¤ Utils/
©¦       ©¸©¤©¤ Constants.swift
©À©¤©¤ Server/               # Node.js backend
©¦   ©À©¤©¤ server.js
©¦   ©¸©¤©¤ package.json
©À©¤©¤ README.md
©¸©¤©¤ ARCHITECTURE.md       # Technical details
```

## Game Rules

### Setup
- Standard 52-card deck (no jokers)
- Each player receives 4 face-down cards
- Players peek at 2 of their own cards at game start
- Remember your cards!

### Turn Structure
1. **Draw**: Take from deck OR discard pile
2. **Action**: Either:
   - Replace one of your face-down cards (discards old card)
   - Discard the drawn card (may use ability if applicable)

### Card Abilities

| Card | Ability |
|------|---------|
| 7, 8 | Peek at one of YOUR cards |
| 9, 10 | Peek at one of an OPPONENT's cards |
| J, Q | Swap a card between you and an opponent |
| A-6, K | No special ability |

### Reaction (Speed Play)
- When a card is discarded, a 5-second window opens
- Any player with a matching rank can immediately play it
- First valid reaction wins and takes the next turn
- This lets you shed cards faster!

### Calling Cabo
- At the START of your turn (before drawing), you may call "Cabo"
- Each other player gets one final turn
- Then all cards are revealed and scored

### Scoring
| Card | Points |
|------|--------|
| Ace | 1 |
| 2-10 | Face value |
| J, Q, K | 10 |

**Lowest score wins!**

## Technical Stack

- **UI**: SwiftUI (iOS 16+)
- **Networking**: URLSession WebSocket
- **Architecture**: MVVM with Combine
- **Server**: Node.js with `ws` library
- **State Management**: ObservableObject + @Published

## Configuration

### Server URL
Edit `ServerConfig` in `WebSocketManager.swift`:

```swift
struct ServerConfig {
    static let defaultHost = "your-server.com"
    static let defaultPort = 8080
    static let websocketPath = "/ws"
}
```

### Timers
In `server.js`:
- `REACTION_WINDOW_MS`: 5000 (5 seconds)
- `TURN_TIME_LIMIT_MS`: 60000 (60 seconds)

## Network Protocol

Messages are JSON with this structure:

```json
{
    "type": "playerAction",
    "timestamp": "2024-01-15T12:00:00Z",
    "payload": {
        "type": "action",
        "playerId": "uuid",
        "action": { "type": "drawCard", "source": "deck" }
    }
}
```

See `ARCHITECTURE.md` for complete protocol documentation.

## Security

- **Authoritative Server**: All game logic validated server-side
- **Hidden Information**: Other players' face-down cards are never sent to clients
- **Timing Enforcement**: Reaction windows strictly enforced on server

## Future Roadmap

- [ ] AI players for solo practice
- [ ] Game Center integration
- [ ] Persistent player profiles
- [ ] Additional game variants
- [ ] Spectator mode
- [ ] Sound effects and music

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - feel free to use this for learning or your own projects!

