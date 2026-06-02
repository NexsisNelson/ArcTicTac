# TicTacToe Arc - UI/UX Design Mockup

## Design Philosophy
- **Clean & Minimal**: Avoid clutter; focus on game board and key actions
- **Mobile-First**: Primary platform is Flutter (iOS/Android)
- **Accessibility**: High contrast, readable fonts, clear CTAs
- **Performance**: Lightweight animations, fast state updates
- **Web3-Ready**: Wallet connection & gas fees visible but not intrusive

---

## Color Scheme
| Element | Color | Hex |
|---------|-------|-----|
| Primary | Deep Blue | #1E40AF |
| Secondary | Orange | #F97316 |
| Success | Green | #16A34A |
| Danger | Red | #DC2626 |
| Background | Near Black | #0F172A |
| Surface | Dark Slate | #1E293B |
| Text (Primary) | Off-White | #F8FAFC |
| Text (Secondary) | Gray | #94A3B8 |

---

## Typography
- **Headlines (H1–H3)**: Inter Bold, 24–32px
- **Body Text**: Inter Regular, 14–16px
- **Buttons**: Inter Medium, 14–16px
- **Accent**: Inter SemiBold, 12–14px

---

## Screen Designs

### 1. Splash/Loading Screen
```
┌─────────────────────────────────┐
│                                 │
│        🎮 TicTacToe Arc          │
│      Blockchain Gaming           │
│                                 │
│        [Loading spinner]         │
│      Initializing Firebase...    │
│                                 │
│   "Loading faster every time"    │
│                                 │
└─────────────────────────────────┘

Duration: 2–3 seconds
Action: Auto-navigate to Home Screen after init
```

---

### 2. Home Screen (Main Menu)
```
┌─────────────────────────────────┐
│  TicTacToe Arc          [⚙️]     │
├─────────────────────────────────┤
│                                 │
│   Your Rating: 1250 ELO         │
│   Matches Played: 12            │
│   Win Rate: 58.3%               │
│                                 │
│ ┌─────────────────────────────┐ │
│ │  ▶️ PLAY OFFLINE            │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │  🌐 PLAY ONLINE             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │  💰 PLACE BET               │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │  👤 PROFILE / LEADERBOARD   │ │
│ └─────────────────────────────┘ │
│                                 │
│    [ Your Wallet: Disconnected ]│
│                                 │
└─────────────────────────────────┘

Key Elements:
- Stats widget at top (prominent ELO)
- 4 primary action buttons (large, tappable)
- Wallet status at bottom (green if connected)
- Settings icon (top-right)
```

---

### 3. Offline Game Screen
```
┌─────────────────────────────────┐
│  Offline Game            [⏸️]    │
├─────────────────────────────────┤
│                                 │
│       X: You      O: AI (Random)│
│                                 │
│   ┌─────┬─────┬─────┐           │
│   │     │  X  │     │           │
│   ├─────┼─────┼─────┤           │
│   │  O  │     │  X  │           │
│   ├─────┼─────┼─────┤           │
│   │     │  O  │     │           │
│   └─────┴─────┴─────┘           │
│                                 │
│   X to move (You)               │
│   [Tap to place your mark]      │
│                                 │
│                                 │
│  [ RESTART ]  [ BACK TO MENU ]  │
│                                 │
└─────────────────────────────────┘

Interaction:
- Tap empty cell to place X
- AI responds with O (1–2s delay)
- Highlight current player's color
- Show game status (move count, turn)
- Celebratory animation on win/draw
```

---

### 4. Online Game Screen (Waiting for Opponent)
```
┌─────────────────────────────────┐
│  Finding Opponent...     [⏱️ 12s]│
├─────────────────────────────────┤
│                                 │
│   ⏳ Waiting for Player...       │
│                                 │
│   Matching Criteria:            │
│   • ELO Range: 1050–1450        │
│   • Bet: None (No Stake)        │
│   • Timeout in: 12 seconds      │
│                                 │
│   [Searching animation...]      │
│                                 │
│                                 │
│                                 │
│  [ CANCEL ]                     │
│                                 │
└─────────────────────────────────┘

Behavior:
- Show countdown timer (30s total)
- Display matching criteria
- Pulsing "Searching" indicator
- Allow cancel (abort match creation)
- Auto-cancel if timeout expires
```

---

### 5. Online Game Screen (Playing)
```
┌─────────────────────────────────┐
│  Match #5432          [⏱️ 4:23]  │
├─────────────────────────────────┤
│  You (X) 1250 ELO                │
│                                 │
│   ┌─────┬─────┬─────┐           │
│   │  X  │  O  │     │           │
│   ├─────┼─────┼─────┤           │
│   │     │  X  │  O  │           │
│   ├─────┼─────┼─────┤           │
│   │     │     │     │           │
│   └─────┴─────┴─────┘           │
│                                 │
│  Opponent (O) 1310 ELO           │
│  [Status: Move received]        │
│                                 │
│  Bet: None                      │
│                                 │
│  [ RESIGN ]  [ BACK (Minimise) ]│
│                                 │
└─────────────────────────────────┘

Key Details:
- Your player at top, opponent at bottom
- Active player highlighted in color
- Board cells are large, tappable
- Timer shows elapsed match time
- Bet amount displayed (if applicable)
- Move indicator: "Your turn" vs "Waiting..."
- Resign/forfeit button available
```

---

### 6. Match Result Screen
```
┌─────────────────────────────────┐
│  Match Finished              ✅  │
├─────────────────────────────────┤
│                                 │
│        🏆 YOU WIN! 🏆           │
│                                 │
│  X (You)      vs      O (Opp)   │
│  1250 ELO              1310 ELO  │
│                                 │
│   Final Board:                  │
│   ┌─────┬─────┬─────┐           │
│   │  X  │  X  │  X  │ ✓         │
│   ├─────┼─────┼─────┤           │
│   │  O  │  O  │     │           │
│   ├─────┼─────┼─────┤           │
│   │     │     │     │           │
│   └─────┴─────┴─────┘           │
│                                 │
│   ELO Change:                   │
│   You: 1250 → 1260 (+10)        │
│   Opponent: 1310 → 1300 (-10)   │
│                                 │
│   Match Duration: 3:45          │
│   Bet: None                     │
│                                 │
│  [ PLAY AGAIN ]  [ HOME ]       │
│                                 │
└─────────────────────────────────┘

Variations:
- Loss: "YOU LOST" (red), ELO decreases
- Draw: "DRAW" (yellow), both get +0.5× K-factor
- With Bet: Show USDC payout/loss
```

---

### 7. Wallet Connection Screen
```
┌─────────────────────────────────┐
│  Connect Wallet              [✕] │
├─────────────────────────────────┤
│                                 │
│   To enable betting, connect    │
│   your Arc testnet wallet.      │
│                                 │
│   ┌─────────────────────────────┐│
│   │  🔗 CONNECT WALLET          ││
│   │   (WalletConnect)           ││
│   └─────────────────────────────┘│
│                                 │
│   Supported Wallets:            │
│   • MetaMask                    │
│   • Trust Wallet                │
│   • Coinbase Wallet             │
│   • Rainbow                     │
│                                 │
│   Network: Arc Testnet (USDC)   │
│   Min Balance: 1 USDC           │
│                                 │
│   [ SKIP FOR NOW ]              │
│                                 │
└─────────────────────────────────┘

Interaction:
- Tap "CONNECT WALLET"
- Display WalletConnect QR code
- User scans with mobile wallet
- Approve connection in wallet
- Return to app with address
- Show wallet balance & chain
```

---

### 8. Bet Setup Screen (Pre-Match)
```
┌─────────────────────────────────┐
│  Set Bet Amount              [✕] │
├─────────────────────────────────┤
│                                 │
│   Opponent Rating: 1310         │
│   Estimated ELO Gain: +12       │
│                                 │
│   USDC Balance: 50.00           │
│                                 │
│   ┌─────────────────────────────┐│
│   │ Bet Amount (USDC)           ││
│   │                             ││
│   │ [$_______]                 ││
│   │  0         50               ││
│   │  Min: 1    Max: 50         ││
│   └─────────────────────────────┘│
│                                 │
│   Potential Payout:             │
│   Win: 19.80 USDC (+9.80)       │
│   Loss: 0 USDC (-[amount])      │
│   Draw: [amount] USDC (refund)  │
│                                 │
│   ⚠️ Bet is locked when match    │
│      starts. No withdrawal until │
│      game ends.                 │
│                                 │
│  [ CANCEL ]  [ CONFIRM BET ]    │
│                                 │
└─────────────────────────────────┘

UX Notes:
- Slider for quick bet selection
- Real-time payout calculation
- Warning about bet lock-in
- Show remaining balance after bet
```

---

### 9. Leaderboard Screen
```
┌─────────────────────────────────┐
│  Leaderboard            [Search] │
├─────────────────────────────────┤
│  Top Players (This Week)        │
│                                 │
│  1.  🥇 Alice     1580 ELO      │
│      12 Wins, 2 Losses          │
│                                 │
│  2.  🥈 Bob       1520 ELO      │
│      10 Wins, 1 Loss            │
│                                 │
│  3.  🥉 Charlie   1480 ELO      │
│      9 Wins, 3 Losses           │
│                                 │
│  4.     Diana    1450 ELO       │
│      8 Wins, 2 Losses           │
│                                 │
│  5.     YOU      1250 ELO       │
│      6 Wins, 4 Losses           │
│                                 │
│  [All Time]  [This Week]  [Today]│
│                                 │
│                                 │
└─────────────────────────────────┘

Features:
- Filterable by time period
- Show rank, name, ELO, W/L record
- Highlight current user
- Tap to view player profile
```

---

### 10. Settings Screen
```
┌─────────────────────────────────┐
│  Settings                    [✕] │
├─────────────────────────────────┤
│                                 │
│  GAME                           │
│  [ ] Auto-accept rematches      │
│  [ ] Sound Enabled              │
│  [ ] Haptic Feedback            │
│                                 │
│  WALLET                         │
│  Connected: MetaMask            │
│  Address: 0x1a2B...9Cd4         │
│  [ DISCONNECT WALLET ]          │
│                                 │
│  NOTIFICATIONS                  │
│  [ ] Match Found                │
│  [ ] Match Finished             │
│  [ ] Opponent Resignation       │
│                                 │
│  ABOUT                          │
│  Version: 0.0.1                 │
│  Build: 42                      │
│  [ TERMS & CONDITIONS ]         │
│  [ PRIVACY POLICY ]             │
│  [ REPORT BUG ]                 │
│                                 │
│                                 │
└─────────────────────────────────┘

Actions:
- Toggle sound, haptics, notifications
- Disconnect wallet
- View legal docs
- Report bugs (opens email)
```

---

## User Flows

### Flow 1: Offline Game
```
Home
  ↓
[Play Offline]
  ↓
Offline Game (vs AI)
  ↓
Result → [Play Again or Back to Home]
```

### Flow 2: Online Game (No Bet)
```
Home
  ↓
[Play Online]
  ↓
Waiting Screen (30s timeout)
  ↓
Opponent Found
  ↓
Online Game (Turn-based, Real-time)
  ↓
Match Finished (ELO updated)
  ↓
Result Screen → [Play Again or Home]
```

### Flow 3: Online Game (With Bet)
```
Home
  ↓
[Play Online] → [Place Bet]
  ↓
Wallet not connected?
  ├─ Yes → [Connect Wallet] → Check Balance
  └─ No → Proceed
  ↓
[Set Bet Amount] → [Confirm Bet]
  ↓
Waiting Screen (match creation)
  ↓
Opponent Found
  ↓
Escrow Contract Locks Stakes (2 signatures)
  ↓
Online Game (Turn-based, Real-time)
  ↓
Match Finished
  ↓
Server validates board → Escrow resolves
  ↓
Result Screen (show USDC payout/loss)
  ↓
[Play Again or Home]
```

### Flow 4: Wallet Connection
```
Home / Settings
  ↓
[Connect Wallet]
  ↓
Display WalletConnect QR Code
  ↓
User scans with mobile wallet
  ↓
Approve connection in wallet app
  ↓
Return to TicTacToe App
  ↓
Display connected wallet address & balance
```

---

## Animation & Micro-interactions

| Element | Interaction | Animation |
|---------|-------------|-----------|
| Board Cell | Tap | Bounce (50ms), color fill (150ms) |
| Win Animation | Match ends in 3-in-a-row | Draw line through 3 cells, pulse (1s) |
| ELO Update | Result screen | Number rolls from old → new (500ms) |
| Wallet Connect | QR displayed | Subtle fade-in (300ms) |
| Match Found | Opponent joins | Slide-in notification (300ms) |
| Bet Payout | Bet resolved | Gold coin animation (1s) |

---

## Accessibility

1. **Color Contrast**: All text meets WCAG AA standards (4.5:1 ratio)
2. **Font Sizes**: Minimum 14px for body, 24px for headers
3. **Button Touch Target**: Minimum 44×44 points (iOS guideline)
4. **Focus Indicators**: Visible outline on interactive elements
5. **Screen Reader**: Semantic HTML labels, alt text for icons
6. **Dark Mode**: All colors optimized for dark backgrounds (OLED-friendly)

---

## Responsive Design

- **Primary Target**: Mobile (375–480px width)
- **Secondary Target**: Tablet (600–1024px width)
- **Desktop** (Web): 1200px+ width (future)

| Breakpoint | Board Size | Font Scale |
|------------|-----------|-----------|
| Mobile | 200×200px (6 cols) | 1.0× |
| Tablet | 300×300px (8 cols) | 1.2× |
| Desktop | 400×400px (12 cols) | 1.4× |

---

## Technical Implementation Notes

- **State Management**: Provider or GetX for state (e.g., `game_state`, `wallet_state`)
- **Navigation**: GoRouter for deep linking
- **Animations**: Flutter built-in (`AnimationController`, `Tween`) + `animations` package
- **Responsive**: `MediaQuery` + `LayoutBuilder` for flexible layouts
- **Forms**: `flutter_form_builder` for wallet setup & bet screens
- **Charts**: (Leaderboard ELO sparklines) `fl_chart` package

---

## Future Enhancements

- [ ] Profile photos / avatars
- [ ] Match replay / analysis
- [ ] Streaming integration (Twitch spectate)
- [ ] In-app messaging / post-match chat
- [ ] Multiple game variants (4×4 grid, 4-in-a-row)
- [ ] Tournament brackets
- [ ] Seasonal passes / cosmetic skins
