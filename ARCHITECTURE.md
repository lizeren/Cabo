# Cabo Game Architecture

## Overview

This document describes the architecture of the Cabo multiplayer card game for iOS.

## System Architecture

```
+------------------+          +------------------+
|                  |   WS     |                  |
|   iOS Client     | <------> |   Game Server    |
|   (SwiftUI)      |          |   (Node.js)      |
|                  |          |                  |
+------------------+          +------------------+
        |                              |
        v                              v
+------------------+          +------------------+
|   Game Logic     |          |   Room Manager   |
|   (Local Engine) |          |   (Authoritative)|
+------------------+          +------------------+
```

## Client Architecture (iOS)

### MVVM Pattern

```
Views (SwiftUI)
    |
    v
ViewModels (ObservableObject)
    |
    v
Models / Engine
    |
    v
Networking (WebSocket)
```

### Key Components

#### Models (`Models/`)

| File | Purpose |
|------|---------|
| `Card.swift` | Card, Deck, Suit, Rank definitions |
| `Player.swift` | Player state and card management |
| `GameState.swift` | Complete game state, phases, sanitization |
| `GameAction.swift` | All possible player actions and results |

#### Engine (`Engine/`)

| File | Purpose |
|------|---------|
| `GameEngine.swift` | Core game logic, action processing |
| `TurnStateMachine.swift` | Turn/phase state management |

#### Networking (`Networking/`)

| File | Purpose |
|------|---------|
| `NetworkMessage.swift` | Message types for client-server communication |
| `WebSocketManager.swift` | Connection handling, reconnection logic |
| `GameRoom.swift` | Room management, action processing |

#### ViewModels (`ViewModels/`)

| File | Purpose |
|------|---------|
| `GameViewModel.swift` | Main game state, user actions, UI state |

#### Views (`Views/`)

| File | Purpose |
|------|---------|
| `GameView.swift` | Main game screen, phase routing |
| `LobbyView.swift` | Room creation/joining UI |
| `CardView.swift` | Card rendering (front, back, selection) |
| `PlayerHandView.swift` | Player's cards display |

## State Machine

### Game Phases

```
lobby -> initialPeek -> playing <-> reactionWindow -> finalRound -> scoring -> gameOver
                          ^                              |
                          |______________________________|
                                   (cabo called)
```

### Turn Phases

```
drawing -> deciding -> usingAbility -> selectingTarget -> (reaction window)
              |
              v
         replaceCard
```

## Message Protocol

### Client -> Server

```json
{
    "type": "playerAction",
    "timestamp": "ISO8601",
    "payload": {
        "type": "action",
        "playerId": "UUID",
        "action": {
            "type": "drawCard",
            "source": "deck"
        }
    }
}
```

### Server -> Client

```json
{
    "type": "gameStateUpdate",
    "timestamp": "ISO8601",
    "payload": {
        "type": "gameStateUpdate",
        "state": { ... sanitized game state ... }
    }
}
```

## Security Considerations

### Authoritative Server
- All game logic validated server-side
- Card positions hidden from non-owners
- Drawn cards only sent to drawing player
- Reaction timing enforced server-side

### State Sanitization
- Other players' face-down cards replaced with placeholder
- Drawn card hidden from non-current players
- Deck contents never sent to clients

## Reaction System

```
+-------------------+
|   Card Discarded  |
+-------------------+
          |
          v
+-------------------+
| Start 5s Timer    |
+-------------------+
          |
          v
+-------------------+       +-------------------+
| Wait for Reaction | ----> | First Valid Wins  |
+-------------------+       +-------------------+
          |                          |
          v                          v
+-------------------+       +-------------------+
| Timer Expires     |       | Reacting Player   |
| Advance Turn      |       | Gets Next Turn    |
+-------------------+       +-------------------+
```

## Reconnection Flow

```
1. Client detects disconnect
2. Mark player as "disconnected" on server
3. Client attempts reconnection (exponential backoff)
4. On reconnect:
   - Send reconnect message with playerId + roomCode
   - Server validates player exists
   - Server marks player as "playing"
   - Server sends current game state
   - Broadcast reconnection to other players
```

## Card Abilities

| Rank | Ability | Target Selection |
|------|---------|------------------|
| 7, 8 | Peek Own | Select own card position |
| 9, 10 | Peek Other | Select opponent + position |
| J, Q | Swap | Select own position + opponent + their position |
| Others | None | N/A |

## Scoring

```swift
func calculateScore() -> Int {
    cards.reduce(0) { total, card in
        switch card.rank {
        case .ace: total + 1
        case .jack, .queen, .king: total + 10
        default: total + card.rank.rawValue
        }
    }
}
```

## UI/UX Design

### Color Palette
- Background: `#0D1117` (deep midnight)
- Card Table: `#161B22`
- Primary Accent: `#58A6FF` (electric blue)
- Secondary: `#7EE787` (success green)
- Danger: `#F85149` (alert red)
- Reaction: `#A371F7` (purple pulse)

### Touch Interactions
- Tap card to select
- Tap deck/discard to draw
- Tap own card to replace with drawn card
- Hold card during reaction window to react

### Visual Feedback
- Selected cards scale up 5%
- Reaction-eligible cards pulse with purple glow
- Active player highlighted with green border
- Timer changes color: green -> yellow -> red

## Future Enhancements

1. **AI Players**
   - Implement `AIPlayer` conforming to player protocol
   - Simple strategy: track known cards, minimize score

2. **Game Variants**
   - Two-joker variant (jokers = 0 points)
   - Team play mode
   - Speed mode (shorter timers)

3. **Persistence**
   - Player profiles and statistics
   - Match history
   - Leaderboards

4. **Polish**
   - Card flip animations
   - Sound effects
   - Haptic patterns for different actions

