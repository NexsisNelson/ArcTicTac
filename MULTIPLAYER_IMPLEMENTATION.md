# Online Multiplayer Networking Implementation

## Overview
This document details the real-time online multiplayer system for TicTacToe Arc, powered by Firebase Realtime Database and enhanced with move validation, opponent tracking, and robust timeout handling.

---

## Architecture

### High-Level Flow
```
┌─────────────────────────────────────────────────────┐
│ Player A: Find Match                                │
├─────────────────────────────────────────────────────┤
│  1. Query waiting matches (ELO ±200)                │
│  2. Transactional join attempt                      │
│  3. Success → Start game listener                   │
│     or Create new "waiting" match                   │
│  4. Countdown timer starts (30s)                    │
│  5. Opponent found → Transition to "playing"        │
│  6. Real-time board sync                            │
│  7. Game ends → ELO updated                         │
│  8. Results screen                                  │
└─────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. State Management

#### Match State Fields
```dart
String? _opponent;              // Opponent's UID
int _opponentRating;            // Opponent's ELO rating
DateTime? _matchStartTime;      // When match started
DateTime? _waitTimeoutTime;     // When waiting expires
Timer? _waitTimer;              // Countdown timer
int _secondsUntilTimeout;       // Remaining seconds
bool _isWaiting;                // Waiting for opponent?
bool _isConnecting;             // Connection in progress?
String _connectionStatus;       // Human-readable status
int _lastMoveTimestamp;         // Anti-spam measure
```

### 2. Firebase Data Structure

#### Match Document
```json
{
  "matches": {
    "matchId123": {
      "player1": "uid_alice",
      "player1_rating": 1250,
      "player2": "uid_bob",
      "player2_rating": 1310,
      "board": ["X", "O", "", "X", "", "", "", "", ""],
      "current": "O",
      "status": "playing",
      "createdAt": 1717315200000,
      "matchStartTime": 1717315205000,
      "expiresAt": 1717315230000,
      "lastMoveTime": 1717315210500,
      "result": "X wins"
    }
  }
}
```

#### User Document
```json
{
  "users": {
    "uid_alice": {
      "rating": 1260,
      "lastSeen": 1717315220000,
      "matchesPlayed": 12,
      "wins": 7,
      "losses": 5
    }
  }
}
```

---

## Key Features

### 1. Matchmaking with ELO Window

**Algorithm:**
```dart
1. Fetch current user's rating
2. Query all "waiting" matches sorted by creation time
3. For each candidate:
   a. Check if expired (createdAt + 30s)
   b. Check ELO difference (must be ±200 from player's rating)
   c. Attempt transactional join
4. If no suitable match found:
   a. Create new "waiting" match
   b. Start 30-second countdown
   c. Listen for opponent join
```

**Transactional Join:**
```dart
ref.runTransaction((mutableData) {
  if (mutableData.player2 != null) return Transaction.abort();
  if (mutableData.expiresAt < now) return Transaction.abort();
  mutableData.player2 = currentUserId;
  mutableData.player2_rating = myRating;
  mutableData.status = 'playing';
  mutableData.matchStartTime = now;
  return Transaction.success(mutableData);
});
```

**Benefits:**
- No race conditions (two players can't join same match)
- Expired matches auto-ignored
- ELO matching ensures fair gameplay

### 2. Move Validation

**Client-Side Validation:**
```dart
1. Check if move is in valid cell (0-8)
2. Check if cell is empty
3. Check if it's the player's turn
4. Verify move sequence validity:
   - X count <= O count (X goes first)
   - X count == O count or X count == O count + 1
5. Rate limiting (500ms between moves)
6. Verify no winner exists before move
```

**Move Data:**
```dart
{
  'board': [...updated board...],
  'current': 'X' or 'O',
  'status': 'X to move' | 'O to move' | 'X wins' | 'O wins' | 'Draw',
  'lastMoveTime': ServerValue.timestamp,
}
```

### 3. Waiting Timeout (30 seconds)

**Timer Lifecycle:**
```dart
_startWaitCountdown() {
  Timer.periodic(Duration(seconds: 1), (timer) {
    final remaining = _waitTimeoutTime.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      timer.cancel();
      _leaveMatch(); // Auto-leave
    } else {
      setState(() => _secondsUntilTimeout = remaining);
    }
  });
}
```

**User Experience:**
- Countdown displayed prominently: "⏱️ 12 s"
- Auto-leave if no opponent joins
- Snackbar notifies user of timeout
- Can manually leave anytime

### 4. Real-Time Board Synchronization

**Listener:**
```dart
_matchRef.onValue.listen((event) {
  final match = event.snapshot.value;
  setState(() {
    board = match['board'];
    current = match['current'];
    status = match['status'];
    _matchStartTime = DateTime.fromMillisecondsSinceEpoch(match['matchStartTime']);
  });
  
  // Auto-trigger ELO if game ended
  if (match['status'].contains('wins') || match['status'] == 'Draw') {
    _handleMatchEnd(match);
  }
});
```

**Synchronization Guarantees:**
- Firebase ensures all clients see consistent state
- Changes propagate within 100–500ms typically
- Move timestamp prevents stale moves

### 5. Opponent Tracking

**Opponent Info Display:**
```
┌────────────────────────────┐
│ You (X) - 1250 ELO         │
│ vs                         │
│ Opponent - 1310 ELO        │
├────────────────────────────┤
│ Connected ✓                │
│ Time: 3m 45s               │
└────────────────────────────┘
```

**Implementation:**
```dart
if (_symbol == 'O' && _opponent == null) {
  _opponent = matchData['player1'];
  _opponentRating = matchData['player1_rating'];
}
```

### 6. Connection Status Management

**Status Flow:**
```
Offline
  ↓
[Find Match]
  ↓
Connecting... (isConnecting = true)
  ↓
Waiting for opponent... (isWaiting = true, countdown active)
  ↓
Connected (opponent joined, status = 'playing')
  ↓
In Game (turns proceeding)
  ↓
Match Finished (status = 'X wins'/'O wins'/'Draw')
  ↓
Offline (after leaving)
```

**Status Indicators:**
- 🟢 **Connected**: Active game, opponent responsive
- 🟠 **Waiting**: Searching for opponent (30s timer)
- 🔴 **Disconnected**: No active match
- ⚠️ **Connection Failed**: Network error

---

## Disconnection Handling

### Scenarios

| Scenario | Behavior | Recovery |
|----------|----------|----------|
| Player leaves while waiting | Match removed from queue | N/A (no opponent yet) |
| Player leaves during game (X) | Match deleted | Opponent gets loss |
| Player leaves during game (O) | Match reverts to "waiting" | Opponent can rejoin |
| Network timeout (30s+) | Auto-disconnect | Manual rejoin required |

### Graceful Leave:
```dart
Future<void> _leaveMatch() async {
  _matchSub?.cancel();
  _waitTimer?.cancel();
  
  if (_symbol == 'X') {
    await _matchRef.remove(); // Creator removes entire match
  } else {
    await _matchRef.update({
      'player2': null,
      'status': 'waiting'
    }); // Joiner clears themselves
  }
  
  // Reset local state
  _matchRef = null;
  _opponent = null;
  _onlineMode = false;
}
```

---

## ELO Rating System

### Calculation Formula
```
Expected Score = 1 / (1 + 10^((Opponent Rating - Your Rating) / 400))
New Rating = Old Rating + K × (Actual Score - Expected Score)
```

Where:
- **K Factor**: 32 (standard competitive rating)
- **Actual Score**: 1.0 (win), 0.5 (draw), 0.0 (loss)

### Example
```
Player A: 1250 ELO
Player B: 1310 ELO

A's Expected Score = 1 / (1 + 10^((1310-1250)/400)) = 0.4289
B's Expected Score = 1 - 0.4289 = 0.5711

If A wins:
  A's New Rating = 1250 + 32 × (1.0 - 0.4289) = 1250 + 18.27 = 1268
  B's New Rating = 1310 + 32 × (0.0 - 0.5711) = 1310 - 18.27 = 1292

If Draw:
  A's New Rating = 1250 + 32 × (0.5 - 0.4289) = 1250 + 2.27 = 1252
  B's New Rating = 1310 + 32 × (0.5 - 0.5711) = 1310 - 2.27 = 1308
```

---

## Move Validation Example

### Valid Move Sequence
```
Board: [X, O, _, X, _, _, _, _, _]
X: 2, O: 2
✓ Valid (X count = O count + 1, X went first)
```

### Invalid Move Sequences
```
Board: [X, X, _, _, _, _, _, _, _]
X: 2, O: 0
✗ Invalid (X played twice without O)

Board: [X, O, O, _, _, _, _, _, _]
X: 1, O: 2
✗ Invalid (O has more pieces than X)

Board: [X, O, X, X, _, X, _, _, _]
X: 4, O: 1
✗ Invalid (move imbalance)
```

---

## UI/UX Integration

### Match States Visualization

**State 1: Waiting**
```
┌──────────────────────────────┐
│ Finding Opponent...  ⏱️ 18 s  │
├──────────────────────────────┤
│ Criteria:                    │
│ • ELO Range: 1050–1450       │
│ • Searching...               │
│                              │
│ [CANCEL]                     │
└──────────────────────────────┘
```

**State 2: Playing**
```
┌──────────────────────────────┐
│ Match #5432       ⏱️ 3m 45s   │
├──────────────────────────────┤
│ You (X) 1250      vs      Bob │
│                        1310   │
├──────────────────────────────┤
│ ┌───┬───┬───┐                │
│ │ X │ O │   │                │
│ ├───┼───┼───┤                │
│ │   │ X │ O │                │
│ ├───┼───┼───┤                │
│ │   │   │   │                │
│ └───┴───┴───┘                │
│                              │
│ [PLAY AGAIN]  [LEAVE GAME]   │
└──────────────────────────────┘
```

---

## Error Handling

### Network Errors
- **Firebase offline**: Cache previous state, queue moves for retry
- **RTC abort**: Gracefully handle transaction rejection
- **Timeout**: Auto-disconnect after 30s no response

### Game Logic Errors
- **Invalid move**: Reject with snackbar message
- **Out-of-turn move**: Ignore, show "Not your turn"
- **Stale board**: Overwrite with server state

---

## Performance Optimizations

1. **Transaction-based joining**: Prevents race conditions
2. **Listener-based sync**: Push updates instead of polling
3. **Rate limiting (500ms)**: Prevents move spam
4. **Timestamp-based validation**: Detect stale moves
5. **Lazy opponent lookup**: Only fetch opponent data on join

---

## Testing Checklist

- [ ] Single match: Player A vs Player B (both players)
- [ ] Waiting timeout: Player A waits 30s with no opponent
- [ ] Match join race: Two players attempt to join same waiting match
- [ ] Invalid moves: Attempt out-of-turn, duplicate, invalid cell moves
- [ ] Disconnection: Player leaves during game, rejoins opponent
- [ ] ELO updates: Verify correct rating changes after win/loss/draw
- [ ] Move validation: Verify move sequences are correct
- [ ] UI responsiveness: Check opponent info displays correctly
- [ ] Timeout handling: Verify countdown timer accuracy

---

## Future Enhancements

1. **Move time limits**: 60-second per-turn limit with forfeit
2. **Rematch system**: Quick play again without re-matchmaking
3. **Spectator mode**: Watch live matches
4. **Replay functionality**: Download match history
5. **Leaderboard**: Track seasonal rankings
6. **Anti-cheat**: Server-side move validation via Cloud Function
7. **Chat**: Post-match messaging
8. **Skill-based matchmaking**: Weight win rate in addition to ELO
