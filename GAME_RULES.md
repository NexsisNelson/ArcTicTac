# TicTacToe Arc - Game Rules & Design Document

## Overview
**TicTacToe Arc** is a competitive two-player TicTacToe game with optional USDC betting on the Arc blockchain testnet. Players compete in real-time multiplayer matches with ELO-based rating systems and can stake USDC tokens on match outcomes through an escrow contract.

---

## Core Game Rules

### Standard TicTacToe Rules
1. **Board**: 3×3 grid (9 cells total)
2. **Symbols**: Player 1 uses `X`, Player 2 uses `O`
3. **Turn Order**: X always plays first
4. **Win Condition**: Three consecutive symbols (horizontal, vertical, or diagonal)
5. **Draw Condition**: All 9 cells filled with no winner
6. **Game Duration**: Typical match ~2–5 minutes

### Win Conditions (Priority)
- **Win by 3-in-a-row**: Immediate victory
- **Draw**: All cells filled, no winner (both players score 0.5 ELO points)
- **Forfeit**: Opponent disconnects for >30 seconds without rejoining = automatic loss

---

## Multiplayer Mechanics

### Match Lifecycle
1. **Waiting State** (30s timeout)
   - Player 1 creates match with ELO rating
   - Match posted to Firebase Realtime DB with 30-second expiry
   - Match visible to players within ±200 ELO window
   
2. **Joining**
   - Player 2 selects a waiting match
   - Transactional join: Firebase transaction ensures no double-join
   - Both players confirmed, match transitions to `playing` state
   - Optional: Escrow contract locks USDC bets (if betting enabled)

3. **Playing**
   - Turn-based moves synchronized via Firebase Realtime DB
   - Each move updates board state in real-time
   - Invalid moves rejected by client-side + server-side validation
   - Disconnect timeout: 30 seconds to reconnect

4. **Finished**
   - Board reaches win/draw condition
   - Server-side Cloud Function validates final board
   - ELO ratings updated atomically
   - Escrow contract resolves bet (winner gets stake + opponent's stake minus 2% operator fee)
   - Match archived in Firebase

### ELO Rating System
- **Starting Rating**: 1200 (all new players)
- **K-Factor**: 32 (standard competitive rating)
- **Formula**:
  ```
  Expected Score = 1 / (1 + 10^((OpponentRating - YourRating) / 400))
  New Rating = Old Rating + K * (Actual Score - Expected Score)
  ```
- **Match Types**:
  - **Win**: Actual Score = 1.0
  - **Draw**: Actual Score = 0.5
  - **Loss**: Actual Score = 0.0

### Matchmaking Constraints
- **ELO Window**: ±200 points (if no match found within 30s, relax to ±300)
- **Timeout Handling**: Expired matches auto-removed from queue
- **Join Window**: Matches visible for 30 seconds before expiration
- **No Self-Matching**: Players cannot join their own matches

---

## Betting Mechanics (Optional, Blockchain-Enabled)

### Prerequisites
- Player must have connected wallet (WalletConnect)
- Player must hold sufficient USDC balance on Arc testnet
- Player must approve escrow contract to spend USDC (ERC20 approval)

### Bet Flow
1. **Propose Bet**: Before joining, Player 2 optionally sets bet amount (e.g., 10 USDC)
2. **Lock Bet**: If accepted, escrow contract locks both players' stakes
3. **Resolve Bet**: Winner receives: `stake × 2 - (stake × 2 × 0.02)` = 1.96× original stake
4. **Operator Fee**: 2% goes to operator wallet for contract maintenance

### Bet Rules
- **Minimum Bet**: 1 USDC
- **Maximum Bet**: No hard limit (player's balance)
- **Refund on Disconnect**: If player disconnects after join, both stakes returned
- **Refund on Draw**: Both players get original stake back
- **One Bet Per Match**: Cannot modify bet after join

### Escrow Contract Guarantees
- Both stakes locked at join time
- No withdrawal until board is final (win/draw/timeout)
- Operator can only withdraw 2% fee
- Contract is non-custodial (players retain control via WalletConnect)

---

## Game States

```
┌─────────────────┐
│   OFFLINE       │ (Local game, no multiplayer)
└────────┬────────┘
         │
         ├─────────────────────────────────┐
         │                                 │
    ┌────▼────────────┐              ┌─────▼──────────────┐
    │ ONLINE: WAITING │              │ ONLINE: JOIN QUEUE │
    │ (30s timeout)   │◄─────────────┤ (select match)     │
    └────┬────────────┘              └────────────────────┘
         │
    ┌────▼──────────┐
    │ ONLINE: PLAYING│
    │ (turn-based)   │
    └────┬───────────┘
         │
    ┌────▼──────────────────┐
    │ ONLINE: FINISHED      │
    │ (Win/Draw/Forfeit)    │
    │ ELO Updated           │
    │ Bet Resolved (if any) │
    └───────────────────────┘
```

---

## Server-Side Validation (Cloud Function)

### Match Completion Validation
Triggered when a player reports match end. Cloud Function verifies:

1. **Final Board State**
   - Exactly 0, 1, or 2 three-in-a-rows (invalid if >2)
   - No moves after win condition met

2. **Move Sequence**
   - Alternating X/O turns
   - X went first
   - No illegal positions

3. **Status Assignment**
   - "X wins", "O wins", or "Draw"
   - Discard if game-ending move violates rules

4. **ELO Update**
   - Compute new ratings for both players
   - Update atomically in `users/{uid}/rating`
   - Record final ratings in match document

5. **Bet Resolution** (if applicable)
   - Call escrow contract to release winner's tokens
   - Record transaction hash in match

---

## Disconnection & Timeout Behavior

| Scenario | Timeout | Resolution |
|----------|---------|------------|
| Player joins waiting match but disconnects | 30s | Match reverts to "waiting", player2 cleared |
| Player in-game disconnects | 30s | Auto-loss for disconnected player |
| Match waiting for 2nd player | 30s | Match auto-deleted from queue |
| Bet locked, match interrupted | N/A | Escrow refunds both stakes + logs error |

---

## Security & Anti-Cheat Measures

1. **Client-Side Validation**: Reject illegal moves before sending
2. **Server-Side Validation**: Cloud Function re-validates entire final board
3. **Timestamp Checks**: Detect impossible move sequences (e.g., 10 moves in 1 second)
4. **Move Signatures**: (Future) Sign moves with private key to prevent impersonation
5. **Rate Limiting**: Firebase Security Rules limit match creation to 1 per 5 seconds per user

---

## Future Enhancements

- [ ] Move time limits (e.g., 60 seconds per turn)
- [ ] Spectator mode (watch live matches)
- [ ] Replay functionality (download match as PGN-like format)
- [ ] Leaderboard with seasonal rankings
- [ ] Chat during matches (with moderation)
- [ ] Achievements/badges (e.g., "Win Streak of 10")
- [ ] Mobile push notifications for match invitations
- [ ] Cross-chain betting (additional tokens besides USDC)
