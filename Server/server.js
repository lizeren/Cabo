const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');

// Configuration
const PORT = process.env.PORT || 8080;
const REACTION_WINDOW_MS = 5000;
const TURN_TIME_LIMIT_MS = 60000;
const HEARTBEAT_INTERVAL_MS = 30000;

// Game state storage
const rooms = new Map();
const playerConnections = new Map();

// Card definitions
const SUITS = ['hearts', 'diamonds', 'clubs', 'spades'];
const RANKS = ['ace', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'jack', 'queen', 'king'];

// Create WebSocket server - listen on all interfaces for LAN access
const wss = new WebSocket.Server({ 
    port: PORT,
    host: '0.0.0.0'  // Listen on all network interfaces
});

console.log(`Cabo Game Server running on port ${PORT}`);
console.log(`Local access: ws://localhost:${PORT}/ws`);
console.log(`LAN access: ws://YOUR_IP:${PORT}/ws`);

// Connection handling
wss.on('connection', (ws) => {
    console.log('New client connected');
    
    ws.isAlive = true;
    ws.playerId = null;
    ws.roomCode = null;
    
    ws.on('pong', () => {
        ws.isAlive = true;
    });
    
    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data);
            handleMessage(ws, message);
        } catch (error) {
            console.error('Error parsing message:', error);
            sendError(ws, 'invalidMessage');
        }
    });
    
    ws.on('close', () => {
        handleDisconnect(ws);
    });
    
    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
});

// Heartbeat to detect dead connections
const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            handleDisconnect(ws);
            return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
    });
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => {
    clearInterval(heartbeatInterval);
});

// Message handling
function handleMessage(ws, message) {
    const { type, payload } = message;
    
    switch (type) {
        case 'createRoom':
            handleCreateRoom(ws, payload);
            break;
        case 'joinRoom':
            handleJoinRoom(ws, payload);
            break;
        case 'leaveRoom':
            handleLeaveRoom(ws, payload);
            break;
        case 'playerAction':
            handlePlayerAction(ws, payload);
            break;
        case 'heartbeat':
            handleHeartbeat(ws, payload);
            break;
        case 'reconnect':
            handleReconnect(ws, payload);
            break;
        default:
            sendError(ws, 'invalidAction');
    }
}

// Room creation
function handleCreateRoom(ws, payload) {
    const { hostName } = payload;
    
    const playerId = uuidv4();
    const roomCode = generateRoomCode();
    
    const room = {
        code: roomCode,
        hostPlayerId: playerId,
        players: [{
            id: playerId,
            name: hostName,
            status: 'waiting',
            cards: [],
            score: 0,
            isHost: true,
            hasCalledCabo: false,
            peeksRemaining: 2
        }],
        phase: 'lobby',
        turnPhase: 'waiting',
        currentPlayerIndex: 0,
        turnOrder: [],
        deck: [],
        discardPile: [],
        drawnCard: null,
        caboCallerId: null,
        playersWithFinalTurn: new Set(),
        reactionDeadline: null,
        turnDeadline: null,
        reactionTimer: null,
        turnTimer: null,
        pendingAbility: null,
        abilityQueue: []  // Queue of {playerId, ability} for players who matched
    };
    
    rooms.set(roomCode, room);
    
    ws.playerId = playerId;
    ws.roomCode = roomCode;
    playerConnections.set(playerId, ws);
    
    const gameState = sanitizeGameState(room, playerId);
    console.log(`Room ${roomCode} created by ${hostName}, sending state with ${gameState.players.length} player(s)`);
    
    send(ws, {
        type: 'roomCreated',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'roomCreated',
            roomCode,
            playerId,
            gameState
        }
    });
}

// Room joining
function handleJoinRoom(ws, payload) {
    const { roomCode, playerName } = payload;
    
    const room = rooms.get(roomCode.toUpperCase());
    
    if (!room) {
        sendError(ws, 'roomNotFound');
        return;
    }
    
    if (room.phase !== 'lobby') {
        sendError(ws, 'gameAlreadyStarted');
        return;
    }
    
    if (room.players.length >= 4) {
        sendError(ws, 'roomFull');
        return;
    }
    
    const playerId = uuidv4();
    
    const player = {
        id: playerId,
        name: playerName,
        status: 'waiting',
        cards: [],
        score: 0,
        isHost: false,
        hasCalledCabo: false,
        peeksRemaining: 2
    };
    
    room.players.push(player);
    
    ws.playerId = playerId;
    ws.roomCode = roomCode.toUpperCase();
    playerConnections.set(playerId, ws);
    
    send(ws, {
        type: 'roomJoined',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'roomJoined',
            playerId,
            gameState: sanitizeGameState(room, playerId)
        }
    });
    
    // Notify others
    broadcastToRoom(room, {
        type: 'playerJoined',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'playerJoined',
            player
        }
    }, playerId);
    
    broadcastGameState(room);
    
    console.log(`${playerName} joined room ${roomCode}`);
}

// Leave room
function handleLeaveRoom(ws, payload) {
    const { playerId } = payload;
    
    const room = rooms.get(ws.roomCode);
    if (!room) return;
    
    removePlayerFromRoom(room, playerId);
    playerConnections.delete(playerId);
    
    ws.playerId = null;
    ws.roomCode = null;
}

// Normalize UUID to lowercase (Swift sends uppercase)
function normalizeUUID(uuid) {
    return uuid ? uuid.toLowerCase() : uuid;
}

// Player actions
function handlePlayerAction(ws, payload) {
    const { playerId, action } = payload;
    const normalizedPlayerId = normalizeUUID(playerId);
    
    const room = rooms.get(ws.roomCode);
    if (!room) {
        sendError(ws, 'roomNotFound');
        return;
    }
    
    const result = processAction(room, normalizedPlayerId, action);
    
    send(ws, {
        type: 'actionResult',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'actionResult',
            result
        }
    });
    
    broadcastGameState(room);
}

// Process game actions
function processAction(room, playerId, action) {
    const actionType = action.type;
    
    switch (actionType) {
        case 'setReady':
            return setPlayerReady(room, playerId, action.isReady);
        case 'startGame':
            return startGame(room, playerId);
        case 'peekInitialCard':
            return peekInitialCard(room, playerId, action.position);
        case 'finishInitialPeek':
            return finishInitialPeek(room, playerId);
        case 'drawCard':
            return drawCard(room, playerId, action.source);
        case 'replaceCard':
            return replaceCard(room, playerId, action.position);
        case 'discardDrawnCard':
            return discardDrawnCard(room, playerId);
        case 'useAbility':
            return useAbility(room, playerId);
        case 'skipAbility':
            return skipAbility(room, playerId);
        case 'peekOwnCard':
            return peekOwnCard(room, playerId, action.position);
        case 'peekOpponentCard':
            return peekOpponentCard(room, playerId, normalizeUUID(action.playerId), action.position);
        case 'swapCards':
            return swapCards(room, playerId, action.myPosition, normalizeUUID(action.opponentId), action.opponentPosition);
        case 'reactWithCard':
            return reactWithCard(room, playerId, action.position);
        case 'callCabo':
            return callCabo(room, playerId);
        default:
            return { type: 'failure', error: 'invalidAction' };
    }
}

// Game logic functions
function setPlayerReady(room, playerId, isReady) {
    const player = room.players.find(p => p.id === playerId);
    if (!player) return { type: 'failure', error: 'invalidPlayer' };
    
    player.status = isReady ? 'ready' : 'waiting';
    return { type: 'success', message: null };
}

function startGame(room, playerId) {
    if (room.hostPlayerId !== playerId) {
        console.log(`Start game rejected: ${playerId} is not host ${room.hostPlayerId}`);
        return { type: 'failure', error: 'invalidAction' };
    }
    
    // Allow single player for testing, or 2+ players
    if (room.players.length < 1) {
        return { type: 'failure', error: 'notEnoughPlayers' };
    }
    
    console.log(`Starting game with ${room.players.length} player(s)`);
    
    // Initialize deck
    room.deck = createShuffledDeck();
    
    // Deal 4 cards to each player in 2x2 grid
    // Layout: positions 0,1 (top row - hidden), positions 2,3 (bottom row - peeked)
    room.players.forEach(player => {
        player.cards = room.deck.splice(0, 4).map((card, index) => ({
            id: uuidv4(),
            card,
            isFaceUp: false,
            position: index
        }));
        player.status = 'playing';
        player.peeksRemaining = 0;  // No manual peeking needed
        player.readyToPlay = false;  // Must confirm they've seen their cards
        // Bottom row cards (positions 2,3) are auto-peeked for this player
        player.peekedPositions = [2, 3];  // Player knows their bottom 2 cards
    });
    
    // Set up turn order
    room.turnOrder = shuffleArray(room.players.map(p => p.id));
    room.currentPlayerIndex = 0;
    
    // Start with empty discard pile
    room.discardPile = [];
    
    // Initial peek phase - players see their bottom 2 cards and must confirm
    room.phase = 'initialPeek';
    room.turnPhase = 'waiting';
    
    console.log(`Game started in room ${room.code} - waiting for players to confirm initial cards`);
    return { type: 'success', message: 'Game started' };
}

function peekInitialCard(room, playerId, position) {
    if (room.phase !== 'initialPeek') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    const player = room.players.find(p => p.id === playerId);
    if (!player || player.peeksRemaining <= 0) {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    if (position < 0 || position >= player.cards.length) {
        return { type: 'failure', error: 'invalidCardPosition' };
    }
    
    player.peeksRemaining--;
    
    return {
        type: 'peekResult',
        card: player.cards[position].card,
        position,
        playerId
    };
}

function finishInitialPeek(room, playerId) {
    if (room.phase !== 'initialPeek') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    const player = room.players.find(p => p.id === playerId);
    if (!player) return { type: 'failure', error: 'invalidPlayer' };
    
    // Mark player as ready (they've confirmed seeing their auto-peeked cards)
    player.readyToPlay = true;
    
    // Check if all players are ready
    const readyCount = room.players.filter(p => p.readyToPlay === true).length;
    const allReady = readyCount === room.players.length;
    
    console.log(`Player ${player.name} ready (${readyCount}/${room.players.length})`);
    
    if (allReady) {
        room.phase = 'playing';
        // NOW auto-draw for first turn
        autoDrawCard(room);
        startTurnTimer(room);
        console.log(`All players ready, starting game in room ${room.code}`);
    }
    
    return { type: 'success', message: null };
}

function drawCard(room, playerId, source) {
    if (!isCurrentPlayer(room, playerId)) {
        return { type: 'failure', error: 'notYourTurn' };
    }
    
    if (room.turnPhase !== 'drawing') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    let card;
    
    if (source === 'deck') {
        if (room.deck.length === 0) {
            reshuffleDiscardIntoDeck(room);
        }
        card = room.deck.shift();
    } else if (source === 'discardPile') {
        if (room.discardPile.length === 0) {
            return { type: 'failure', error: 'invalidAction' };
        }
        card = room.discardPile.pop();
    }
    
    room.drawnCard = card;
    room.turnPhase = 'deciding';
    
    return {
        type: 'peekResult',
        card,
        position: -1,
        playerId
    };
}

function replaceCard(room, playerId, position) {
    if (!isCurrentPlayer(room, playerId)) {
        return { type: 'failure', error: 'notYourTurn' };
    }
    
    if (room.turnPhase !== 'deciding' || !room.drawnCard) {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    const player = room.players.find(p => p.id === playerId);
    if (!player || position < 0 || position >= player.cards.length) {
        return { type: 'failure', error: 'invalidCardPosition' };
    }
    
    const oldCard = player.cards[position].card;
    player.cards[position].card = room.drawnCard;
    room.discardPile.push(oldCard);
    room.drawnCard = null;
    
    // Store pending ability (if any) - will be triggered after reaction window
    const ability = getCardAbility(oldCard);
    room.pendingAbility = ability !== 'none' ? ability : null;
    
    // Always start reaction window first - ability comes after
    startReactionWindow(room, oldCard);
    
    return { type: 'success', message: null };
}

function discardDrawnCard(room, playerId) {
    if (!isCurrentPlayer(room, playerId)) {
        return { type: 'failure', error: 'notYourTurn' };
    }
    
    if (room.turnPhase !== 'deciding' || !room.drawnCard) {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    const card = room.drawnCard;
    room.discardPile.push(card);
    room.drawnCard = null;
    
    // Store pending ability (if any) - will be triggered after reaction window
    const ability = getCardAbility(card);
    room.pendingAbility = ability !== 'none' ? ability : null;
    
    // Always start reaction window first - ability comes after
    startReactionWindow(room, card);
    return { type: 'success', message: null };
}

function useAbility(room, playerId) {
    if (!isCurrentPlayer(room, playerId) || room.turnPhase !== 'usingAbility') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    room.turnPhase = 'selectingTarget';
    return { type: 'success', message: null };
}

function skipAbility(room, playerId) {
    // Allow skip during usingAbility OR selectingTarget (for swap/peek)
    if (!isCurrentPlayer(room, playerId) || 
        (room.turnPhase !== 'usingAbility' && room.turnPhase !== 'selectingTarget')) {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    // Process next in ability queue or advance turn
    processNextAbilityOrAdvance(room);
    return { type: 'success', message: null };
}

function peekOwnCard(room, playerId, position) {
    if (!isCurrentPlayer(room, playerId) || room.turnPhase !== 'selectingTarget') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    const topCard = room.discardPile[room.discardPile.length - 1];
    if (getCardAbility(topCard) !== 'peekOwn') {
        return { type: 'failure', error: 'abilityNotAvailable' };
    }
    
    const player = room.players.find(p => p.id === playerId);
    if (!player || position < 0 || position >= player.cards.length) {
        return { type: 'failure', error: 'invalidCardPosition' };
    }
    
    // Track that player has peeked this position
    if (!player.peekedPositions) player.peekedPositions = [];
    if (!player.peekedPositions.includes(position)) {
        player.peekedPositions.push(position);
    }
    
    // Broadcast peek event to all players (so they know someone is peeking)
    broadcastToRoom(room, {
        type: 'peekPerformed',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'peekPerformed',
            peekerId: playerId,
            peekerName: player.name,
            targetId: playerId,
            targetName: player.name,
            isOwnCard: true
        }
    });
    
    // Process next in ability queue or advance turn
    processNextAbilityOrAdvance(room);
    
    return {
        type: 'peekResult',
        card: player.cards[position].card,
        position,
        playerId
    };
}

function peekOpponentCard(room, playerId, targetPlayerId, position) {
    if (!isCurrentPlayer(room, playerId) || room.turnPhase !== 'selectingTarget') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    if (playerId === targetPlayerId) {
        return { type: 'failure', error: 'invalidPlayer' };
    }
    
    const topCard = room.discardPile[room.discardPile.length - 1];
    if (getCardAbility(topCard) !== 'peekOther') {
        return { type: 'failure', error: 'abilityNotAvailable' };
    }
    
    const targetPlayer = room.players.find(p => p.id === targetPlayerId);
    const player = room.players.find(p => p.id === playerId);
    if (!targetPlayer || position < 0 || position >= targetPlayer.cards.length) {
        return { type: 'failure', error: 'invalidCardPosition' };
    }
    
    // Broadcast peek event to all players (so they know someone is peeking)
    broadcastToRoom(room, {
        type: 'peekPerformed',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'peekPerformed',
            peekerId: playerId,
            peekerName: player ? player.name : 'Unknown',
            targetId: targetPlayerId,
            targetName: targetPlayer.name,
            isOwnCard: false
        }
    });
    
    // Process next in ability queue or advance turn
    processNextAbilityOrAdvance(room);
    
    return {
        type: 'peekResult',
        card: targetPlayer.cards[position].card,
        position,
        playerId: targetPlayerId
    };
}

function swapCards(room, playerId, myPosition, opponentId, opponentPosition) {
    if (!isCurrentPlayer(room, playerId) || room.turnPhase !== 'selectingTarget') {
        return { type: 'failure', error: 'invalidAction' };
    }
    
    if (playerId === opponentId) {
        return { type: 'failure', error: 'invalidPlayer' };
    }
    
    const topCard = room.discardPile[room.discardPile.length - 1];
    if (getCardAbility(topCard) !== 'swap') {
        return { type: 'failure', error: 'abilityNotAvailable' };
    }
    
    const myPlayer = room.players.find(p => p.id === playerId);
    const opponent = room.players.find(p => p.id === opponentId);
    
    if (!myPlayer || !opponent) {
        return { type: 'failure', error: 'invalidPlayer' };
    }
    
    if (myPosition < 0 || myPosition >= myPlayer.cards.length ||
        opponentPosition < 0 || opponentPosition >= opponent.cards.length) {
        return { type: 'failure', error: 'invalidCardPosition' };
    }
    
    // Swap
    const myCard = myPlayer.cards[myPosition].card;
    myPlayer.cards[myPosition].card = opponent.cards[opponentPosition].card;
    opponent.cards[opponentPosition].card = myCard;
    
    // Broadcast swap event to all players for animation
    broadcastToRoom(room, {
        type: 'swapPerformed',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'swapPerformed',
            swapperId: playerId,
            swapperName: myPlayer.name,
            opponentId: opponentId,
            opponentName: opponent.name,
            swapperPosition: myPosition,
            opponentPosition: opponentPosition
        }
    });
    
    // Process next in ability queue or advance turn
    processNextAbilityOrAdvance(room);
    
    return { type: 'success', message: 'Cards swapped' };
}

function reactWithCard(room, playerId, position) {
    if (room.phase !== 'reactionWindow') {
        return { type: 'reactionRejected', reason: 'Reaction window closed' };
    }
    
    // ALL players can react (including current player)
    const player = room.players.find(p => p.id === playerId);
    if (!player || position < 0 || position >= player.cards.length) {
        return { type: 'reactionRejected', reason: 'Invalid card' };
    }
    
    const topDiscard = room.discardPile[room.discardPile.length - 1];
    const playerCard = player.cards[position].card;
    
    // Check if card matches
    if (playerCard.rank !== topDiscard.rank) {
        // PENALTY: Wrong card! Draw a penalty card blindly
        console.log(`Player ${playerId} guessed wrong! Penalty card drawn.`);
        
        if (room.deck.length === 0) {
            reshuffleDiscardIntoDeck(room);
        }
        
        if (room.deck.length > 0) {
            const penaltyCard = room.deck.shift();
            // Add penalty card to player's hand (they now have 5+ cards)
            player.cards.push({
                id: uuidv4(),
                card: penaltyCard,
                isFaceUp: false,
                position: player.cards.length
            });
            console.log(`Player ${player.name} now has ${player.cards.length} cards`);
        }
        
        return { type: 'reactionRejected', reason: 'Wrong card! Penalty card added to your hand.' };
    }
    
    // CORRECT MATCH: Accept reaction
    console.log(`Player ${playerId} matched correctly!`);
    clearTimeout(room.reactionTimer);
    
    // Remove the matched card from player
    const [removedCard] = player.cards.splice(position, 1);
    room.discardPile.push(removedCard.card);
    
    // Reindex remaining cards
    player.cards.forEach((c, i) => c.position = i);
    
    // Check if there's a pending ability - if so, add player to ability queue
    const hasPendingAbility = room.pendingAbility != null;
    
    if (hasPendingAbility) {
        // Add this player to the ability queue (they get to use the ability too!)
        room.abilityQueue.push({
            playerId: playerId,
            ability: room.pendingAbility
        });
        console.log(`Player ${player.name} matched during ability card - added to queue (${room.abilityQueue.length} in queue)`);
        return { type: 'reactionAccepted', playerId };
    }
    
    // No pending ability - normal reaction behavior
    // End reaction window
    clearTimeout(room.reactionTimer);
    room.reactionDeadline = null;
    room.phase = room.caboCallerId ? 'finalRound' : 'playing';
    
    // Check if reacting player is the current player
    const currentPlayerId = room.turnOrder[room.currentPlayerIndex];
    if (playerId === currentPlayerId) {
        // Current player matched their own discard - just advance to next player
        // (they don't get another turn, just got to discard an extra card)
        console.log(`Current player matched their own card - advancing to next player`);
        advanceToNextPlayer(room);
        autoDrawCard(room);
    } else {
        // Different player matched - they get the next turn as reward
        console.log(`Player ${player.name} gets next turn for matching`);
        setCurrentPlayer(room, playerId);
    }
    
    return { type: 'reactionAccepted', playerId };
}

function callCabo(room, playerId) {
    if (room.phase !== 'playing') {
        return { type: 'failure', error: 'cannotCallCaboNow' };
    }
    
    if (!isCurrentPlayer(room, playerId)) {
        return { type: 'failure', error: 'notYourTurn' };
    }
    
    // Can call Cabo during deciding phase (before playing the card)
    if (room.turnPhase !== 'deciding') {
        return { type: 'failure', error: 'cannotCallCaboNow' };
    }
    
    if (room.caboCallerId) {
        return { type: 'failure', error: 'alreadyCalledCabo' };
    }
    
    room.caboCallerId = playerId;
    room.phase = 'finalRound';
    room.playersWithFinalTurn.add(playerId);
    
    const player = room.players.find(p => p.id === playerId);
    if (player) player.hasCalledCabo = true;
    
    advanceToNextPlayer(room);
    
    console.log(`Cabo called in room ${room.code}`);
    return { type: 'success', message: 'Cabo called!' };
}

// Timer management
function startReactionWindow(room, card) {
    room.phase = 'reactionWindow';
    room.turnPhase = 'waiting';  // Clear turn phase - ability is done
    room.reactionDeadline = new Date(Date.now() + REACTION_WINDOW_MS);
    
    room.reactionTimer = setTimeout(() => {
        const hasAbility = endReactionWindow(room);
        if (!hasAbility) {
            // No pending ability - advance to next player
            advanceToNextPlayer(room);
        }
        // If hasAbility is true, current player stays and uses ability
        broadcastGameState(room);
    }, REACTION_WINDOW_MS);
    
    broadcastGameState(room);
}

function endReactionWindow(room) {
    clearTimeout(room.reactionTimer);
    room.reactionDeadline = null;
    
    // Check if there's a pending ability from the discarded card
    if (room.pendingAbility) {
        const currentPlayerId = room.turnOrder[room.currentPlayerIndex];
        const ability = room.pendingAbility;
        room.pendingAbility = null;
        
        // Original player uses ability FIRST
        const finalQueue = [{
            playerId: currentPlayerId,
            ability: ability
        }];
        
        // Sort other matching players by turn order
        if (room.abilityQueue.length > 0) {
            // Sort by position in turn order (starting from current player)
            const sortedMatchers = room.abilityQueue.sort((a, b) => {
                const aIndex = room.turnOrder.indexOf(a.playerId);
                const bIndex = room.turnOrder.indexOf(b.playerId);
                // Calculate distance from current player in turn order
                const currentIdx = room.currentPlayerIndex;
                const aDist = (aIndex - currentIdx + room.turnOrder.length) % room.turnOrder.length;
                const bDist = (bIndex - currentIdx + room.turnOrder.length) % room.turnOrder.length;
                return aDist - bDist;
            });
            finalQueue.push(...sortedMatchers);
        }
        
        room.abilityQueue = finalQueue;
        console.log(`Reaction window ended - ${room.abilityQueue.length} player(s) in ability queue (original player first)`);
    }
    
    // Process the ability queue
    return processAbilityQueue(room);
}

// Process the next player in the ability queue
function processAbilityQueue(room) {
    if (room.abilityQueue.length > 0) {
        const nextInQueue = room.abilityQueue.shift();
        room.phase = room.caboCallerId ? 'finalRound' : 'playing';
        room.turnPhase = 'usingAbility';
        room.currentAbilityPlayer = nextInQueue.playerId;
        room.currentAbilityType = nextInQueue.ability;
        
        // Temporarily set this player as current for ability use
        const playerIndex = room.turnOrder.indexOf(nextInQueue.playerId);
        if (playerIndex !== -1) {
            room.currentPlayerIndex = playerIndex;
        }
        
        console.log(`Ability queue: ${room.players.find(p => p.id === nextInQueue.playerId)?.name} uses ${nextInQueue.ability}`);
        return true;  // Signal that ability is pending - don't advance turn
    }
    
    if (room.caboCallerId) {
        room.phase = 'finalRound';
    } else {
        room.phase = 'playing';
    }
    return false;  // No pending ability - can advance turn
}

// Called after a player uses/skips their ability
function processNextAbilityOrAdvance(room) {
    // Check if there are more players in the ability queue
    if (room.abilityQueue.length > 0) {
        processAbilityQueue(room);
        broadcastGameState(room);
    } else {
        // No more abilities - advance to next player
        advanceToNextPlayer(room);
        broadcastGameState(room);
    }
}

function startTurnTimer(room) {
    clearTimeout(room.turnTimer);
    room.turnDeadline = new Date(Date.now() + TURN_TIME_LIMIT_MS);
    
    room.turnTimer = setTimeout(() => {
        advanceToNextPlayer(room);
        broadcastGameState(room);
    }, TURN_TIME_LIMIT_MS);
}

function advanceToNextPlayer(room) {
    clearTimeout(room.turnTimer);
    
    // Check for game end
    if (room.phase === 'finalRound') {
        const currentPlayerId = room.turnOrder[room.currentPlayerIndex];
        room.playersWithFinalTurn.add(currentPlayerId);
        
        const activePlayerIds = new Set(room.players.filter(p => p.status === 'playing').map(p => p.id));
        const allTaken = [...activePlayerIds].every(id => room.playersWithFinalTurn.has(id));
        
        if (allTaken) {
            endGame(room);
            return;
        }
    }
    
    // Move to next player
    room.currentPlayerIndex = (room.currentPlayerIndex + 1) % room.turnOrder.length;
    
    // AUTO-DRAW: Automatically draw a card for the new current player
    autoDrawCard(room);
    
    startTurnTimer(room);
}

// Auto-draw a card at the start of turn
function autoDrawCard(room) {
    if (room.deck.length === 0) {
        reshuffleDiscardIntoDeck(room);
    }
    
    if (room.deck.length > 0) {
        room.drawnCard = room.deck.shift();
        room.turnPhase = 'deciding';
        console.log(`Auto-drew card for player ${room.turnOrder[room.currentPlayerIndex]}`);
    } else {
        // No cards left, skip to next player
        room.turnPhase = 'waiting';
    }
}

function setCurrentPlayer(room, playerId) {
    const index = room.turnOrder.indexOf(playerId);
    if (index !== -1) {
        room.currentPlayerIndex = index;
        // AUTO-DRAW for the new current player
        autoDrawCard(room);
        startTurnTimer(room);
    }
}

function endGame(room) {
    room.phase = 'scoring';
    clearTimeout(room.turnTimer);
    clearTimeout(room.reactionTimer);
    
    // Reveal all cards and calculate scores
    room.players.forEach(player => {
        player.cards.forEach(c => c.isFaceUp = true);
        player.score = player.cards.reduce((sum, c) => sum + getCardScore(c.card), 0);
    });
    
    // Determine winner
    const sortedPlayers = [...room.players].sort((a, b) => a.score - b.score);
    const winner = sortedPlayers[0];
    
    const result = {
        winnerId: winner.id,
        winnerName: winner.name,
        scores: room.players.map(p => ({
            id: uuidv4(),
            playerId: p.id,
            playerName: p.name,
            score: p.score,
            cards: p.cards.map(c => c.card),
            calledCabo: p.id === room.caboCallerId
        })),
        wasCaboSuccessful: room.caboCallerId === winner.id
    };
    
    room.phase = 'gameOver';
    
    // Broadcast result
    broadcastToRoom(room, {
        type: 'actionResult',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'actionResult',
            result: { type: 'gameEnded', result }
        }
    });
    
    broadcastGameState(room);
    
    console.log(`Game ended in room ${room.code}, winner: ${winner.name}`);
}

// Utility functions
function isCurrentPlayer(room, playerId) {
    return room.turnOrder[room.currentPlayerIndex] === playerId;
}

function getCardAbility(card) {
    const rank = card.rank;
    if (rank === 'seven' || rank === 'eight') return 'peekOwn';
    if (rank === 'nine' || rank === 'ten') return 'peekOther';
    if (rank === 'jack' || rank === 'queen') return 'swap';
    return 'none';
}

function getCardScore(card) {
    const rank = card.rank;
    if (rank === 'ace') return 1;
    if (rank === 'jack' || rank === 'queen' || rank === 'king') return 10;
    const rankIndex = RANKS.indexOf(rank);
    return rankIndex + 1;
}

function createShuffledDeck() {
    const deck = [];
    SUITS.forEach(suit => {
        RANKS.forEach(rank => {
            deck.push({
                id: uuidv4(),
                suit,
                rank
            });
        });
    });
    return shuffleArray(deck);
}

function shuffleArray(array) {
    const arr = [...array];
    for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
}

function reshuffleDiscardIntoDeck(room) {
    if (room.discardPile.length <= 1) return;
    
    const topCard = room.discardPile.pop();
    room.deck = shuffleArray(room.discardPile);
    room.discardPile = [topCard];
}

function generateRoomCode() {
    // Simple 1-digit code for easier debugging (0-9)
    return String(Math.floor(Math.random() * 10));
}

function sanitizeGameState(room, playerId) {
    // For the requesting player, show cards they've peeked
    // For other players, hide all their cards unless face up
    const state = {
        roomCode: room.code,
        hostPlayerId: room.hostPlayerId,
        players: room.players.map(p => {
            const isMe = p.id === playerId;
            const peekedPositions = p.peekedPositions || [];
            
            // Debug log for the requesting player
            if (isMe) {
                console.log(`[Sanitize] Player ${p.name}: peekedPositions=${JSON.stringify(peekedPositions)}`);
            }
            
            return {
                ...p,
                cards: p.cards.map((c, idx) => {
                    // Show card if: it's face up, OR it's my card and I've peeked it
                    const canSee = c.isFaceUp || (isMe && peekedPositions.includes(idx));
                    
                    // Debug log
                    if (isMe) {
                        console.log(`[Sanitize] Card ${idx}: canSee=${canSee}, rank=${canSee ? c.card.rank : 'hidden'}`);
                    }
                    
                    return {
                        ...c,
                        card: canSee ? c.card : { id: c.card.id, suit: 'hidden', rank: 'hidden' },
                        // Mark if this card has been peeked by the player
                        isPeeked: isMe && peekedPositions.includes(idx)
                    };
                }),
                // Include peeked positions only for the requesting player
                peekedPositions: isMe ? peekedPositions : []
            };
        }),
        currentPlayerIndex: room.currentPlayerIndex,
        turnOrder: room.turnOrder,
        phase: room.phase,
        turnPhase: room.turnPhase,
        deckCount: room.deck.length,
        discardPile: room.discardPile,
        drawnCard: isCurrentPlayer(room, playerId) ? room.drawnCard : null,
        caboCallerId: room.caboCallerId,
        playersWithFinalTurn: [...room.playersWithFinalTurn],
        reactionDeadline: room.reactionDeadline?.toISOString() || null,
        turnDeadline: room.turnDeadline?.toISOString() || null,
        turnTimeLimit: TURN_TIME_LIMIT_MS / 1000,
        roundNumber: 1,
        gameScores: {},
        pendingReactions: {}
    };
    
    return state;
}

function removePlayerFromRoom(room, playerId) {
    room.players = room.players.filter(p => p.id !== playerId);
    room.turnOrder = room.turnOrder.filter(id => id !== playerId);
    
    if (room.players.length === 0) {
        clearTimeout(room.turnTimer);
        clearTimeout(room.reactionTimer);
        rooms.delete(room.code);
        console.log(`Room ${room.code} deleted (empty)`);
        return;
    }
    
    // Notify remaining players
    broadcastToRoom(room, {
        type: 'playerLeft',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'playerLeft',
            playerId
        }
    });
    
    broadcastGameState(room);
}

function handleDisconnect(ws) {
    if (ws.playerId && ws.roomCode) {
        const room = rooms.get(ws.roomCode);
        if (room) {
            const player = room.players.find(p => p.id === ws.playerId);
            if (player) {
                player.status = 'disconnected';
                
                broadcastToRoom(room, {
                    type: 'playerDisconnected',
                    timestamp: new Date().toISOString(),
                    payload: {
                        type: 'playerDisconnected',
                        playerId: ws.playerId
                    }
                }, ws.playerId);
                
                broadcastGameState(room);
            }
        }
        
        playerConnections.delete(ws.playerId);
        console.log(`Player ${ws.playerId} disconnected`);
    }
}

function handleReconnect(ws, payload) {
    const { playerId, roomCode } = payload;
    
    const room = rooms.get(roomCode);
    if (!room) {
        sendError(ws, 'roomNotFound');
        return;
    }
    
    const player = room.players.find(p => p.id === playerId);
    if (!player) {
        sendError(ws, 'invalidPlayer');
        return;
    }
    
    player.status = room.phase === 'lobby' ? 'waiting' : 'playing';
    
    ws.playerId = playerId;
    ws.roomCode = roomCode;
    playerConnections.set(playerId, ws);
    
    broadcastToRoom(room, {
        type: 'playerReconnected',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'playerReconnected',
            playerId
        }
    }, playerId);
    
    send(ws, {
        type: 'gameStateUpdate',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'gameStateUpdate',
            state: sanitizeGameState(room, playerId)
        }
    });
    
    console.log(`Player ${player.name} reconnected to room ${roomCode}`);
}

function handleHeartbeat(ws, payload) {
    ws.isAlive = true;
    send(ws, {
        type: 'pong',
        timestamp: new Date().toISOString(),
        payload: { type: 'pong' }
    });
}

// Message sending utilities
function send(ws, message) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(message));
    }
}

function sendError(ws, error) {
    send(ws, {
        type: 'error',
        timestamp: new Date().toISOString(),
        payload: {
            type: 'error',
            result: error
        }
    });
}

function broadcastToRoom(room, message, excludePlayerId = null) {
    room.players.forEach(player => {
        if (player.id !== excludePlayerId) {
            const ws = playerConnections.get(player.id);
            if (ws) send(ws, message);
        }
    });
}

function broadcastGameState(room) {
    room.players.forEach(player => {
        const ws = playerConnections.get(player.id);
        if (ws) {
            send(ws, {
                type: 'gameStateUpdate',
                timestamp: new Date().toISOString(),
                payload: {
                    type: 'gameStateUpdate',
                    state: sanitizeGameState(room, player.id)
                }
            });
        }
    });
}

console.log('Server ready for connections');

