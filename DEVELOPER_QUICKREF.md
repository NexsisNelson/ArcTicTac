# Developer Quick Reference

## 🎯 Project Overview

**Arc TicTac** is a Flutter TicTacToe game with:
- Offline play (local AI)
- Online multiplayer (Firebase + ELO)
- Arc blockchain USDC betting (non-custodial escrow)

**Current Status:** Testnet Ready | All features implemented | Awaiting mainnet migration

---

## 📁 Key Files & Their Purposes

### Frontend (Flutter)

| File | Purpose | Key Code |
|------|---------|----------|
| [lib/main.dart](lib/main.dart) | Main game UI (700+ lines) | `_TicTacToePageState`, `playAt()`, `_startMatchmaking()` |
| [lib/wallet_service.dart](lib/wallet_service.dart) | WalletConnect integration | `WalletService`, `connect()`, `approveToken()` |
| [lib/escrow_service.dart](lib/escrow_service.dart) | Web3 contract interaction | `EscrowService`, `createMatch()`, `deposit()` |
| lib/config.dart | Configuration constants | Contract addresses, RPC URLs |

### Smart Contracts (Solidity)

| File | Purpose | Key Functions |
|------|---------|---------------|
| [contracts/Escrow.sol](contracts/Escrow.sol) | Non-custodial bet escrow | `createMatch()`, `deposit()`, `resolveMatch()` |
| [contracts/ESCROW_DESIGN.md](contracts/ESCROW_DESIGN.md) | Design rationale | Architecture, operator model, security |

### Backend (Cloud Functions)

| File | Purpose | Key Function |
|------|---------|--------------|
| [functions/src/index.ts](functions/src/index.ts) | Match validation | Board verification, ELO calc, escrow resolution |

### Documentation

| File | Purpose | Audience |
|------|---------|----------|
| [README.md](README.md) | Project overview & setup | All developers |
| [contracts/ARC_ESCROW_DEPLOYMENT.md](contracts/ARC_ESCROW_DEPLOYMENT.md) | Deployment guide | Blockchain/DevOps engineers |
| [GAME_RULES.md](GAME_RULES.md) | Game specification | Game/Rules developers |
| [MULTIPLAYER_IMPLEMENTATION.md](MULTIPLAYER_IMPLEMENTATION.md) | Technical architecture | Backend/Firebase engineers |
| [UI_UX_DESIGN.md](UI_UX_DESIGN.md) | UI specification | Frontend/UX designers |

---

## 🚀 Getting Started (5 Minutes)

### 1. Clone & Setup
```bash
git clone https://github.com/NexsisNelson/ArcTicTac.git
cd ArcTicTac
flutter pub get
```

### 2. Run Offline Mode
```bash
flutter run
# Select "Offline" → Play game
```

### 3. Enable Online Multiplayer (Requires Firebase)
```bash
# Create Firebase project
firebase init
firebase deploy --only functions
# Configure in Flutter app
flutter run
# Select "Online" → Anonymous login → Matchmaking
```

### 4. Enable USDC Betting (Requires Arc Testnet)
```bash
# Deploy escrow contract (see contracts/ARC_ESCROW_DEPLOYMENT.md)
# Update lib/config.dart with contract address
# Request test USDC from testnet faucet
flutter run
# Select "Online" → "Place Bet" → Play → Resolve bet
```

---

## 🎮 Feature Walkthrough

### Offline Game
```dart
// User taps cell at index i
playAt(i);

// Validates: 
// - Cell not already played
// - Current player's turn
// - Move sequence valid (X/O counts)
// 
// Updates:
// - Board state
// - Current player
// - Win/draw detection
// - UI refresh
```

### Online Matchmaking
```dart
// User clicks "Find Match"
_startMatchmaking();

// Flow:
// 1. Create waiting entry in Firebase: /matches/[matchId]
// 2. Query other waiting players (ELO ±200 range)
// 3. Transaction join: player2 = current user
// 4. If match found: Join match & start game
// 5. If no match in 30s: Timeout, show retry option
```

### ELO Rating System
```dart
// After game ends (win/loss/draw):
// 1. Cloud Function validates board
// 2. Calculates: Expected = 1 / (1 + 10^((opponent - yours) / 400))
// 3. New rating = Old + 32 * (Actual - Expected)
// 4. Updates Firebase: /users/[uid]/rating
// 5. UI shows +/- change
```

### USDC Betting
```dart
// User places bet:
// 1. escrowService.createMatch(opponent, amount)
//    → Contract creates Match struct, returns matchId
// 
// 2. escrowService.approveUsdc(amount)
//    → Wallet signs ERC20 approve() call
// 
// 3. escrowService.deposit(matchId)
//    → Player's USDC transferred to escrow
// 
// 4. Opponent does same → Match funded
// 
// 5. Game plays normally
// 
// 6. Cloud Function validates & calls:
//    escrowContract.resolveMatch(matchId, winner)
//    → Winner receives: (amount * 2) - 2% fee
//    → Treasury receives: 2% fee
```

---

## 🔧 Common Tasks

### Add a New Screen

1. Create widget in `lib/screens/my_screen.dart`
2. Add route in `main.dart` (Navigator.push)
3. Update navigation menu
4. Test with `flutter run`

### Modify Game Rules

1. Edit win condition in `_checkWin()` (lib/main.dart)
2. Update validation in `playAt()` 
3. Update [GAME_RULES.md](GAME_RULES.md)
4. Test offline mode first

### Change ELO Calculation

1. Modify `_handleMatchEnd()` in lib/main.dart
2. Update Cloud Function in functions/src/index.ts
3. Update [MULTIPLAYER_IMPLEMENTATION.md](MULTIPLAYER_IMPLEMENTATION.md)
4. Redeploy function: `firebase deploy --only functions`

### Deploy Contract Update

1. Edit `contracts/Escrow.sol`
2. Compile: `solc --version` (ensure ^0.8.19)
3. Deploy to Arc testnet (Remix or Hardhat)
4. Update contract address in `lib/config.dart`
5. Update escrow_service.dart if ABI changed

### Add New Firebase Field

1. Write to path: `await _database.ref('path').set(value)`
2. Read from path: `await _database.ref('path').get()`
3. Add listeners: `_database.ref('path').onValue.listen(...)`
4. Document in [MULTIPLAYER_IMPLEMENTATION.md](MULTIPLAYER_IMPLEMENTATION.md)

---

## 📊 Data Models

### Match (Firebase)
```dart
{
  "matchId": "uuid",
  "player1": "user123",
  "player2": "user456",
  "rating1": 1600,
  "rating2": 1200,
  "board": [0,0,1,2,1,0,0,0,2],  // 0=empty, 1=X, 2=O
  "currentPlayer": 1,
  "status": "playing",  // waiting → playing → finished
  "winner": 1,  // 0=draw, 1=player1, 2=player2, null=unfinished
  "bettingEnabled": true,
  "betAmount": "1000000000000000000",  // 1 USDC in wei
  "escrowMatchId": 123,
  "createdAt": 1700000000,
  "updatedAt": 1700000060
}
```

### User (Firebase)
```dart
{
  "uid": "user123",
  "username": "Player One",
  "rating": 1600,
  "wins": 42,
  "losses": 15,
  "draws": 3,
  "walletAddress": "0x123...",
  "lastPlayedAt": 1700000000
}
```

### Match (Escrow Contract)
```solidity
struct Match {
  address player1;           // Bettor 1
  address player2;           // Bettor 2
  address token;             // USDC token
  uint256 amount;            // Bet per player
  bool p1Deposited;          // Player 1 stake locked
  bool p2Deposited;          // Player 2 stake locked
  Status status;             // Waiting → Funded → Playing → Resolved
  uint256 createdAt;         // Block timestamp
  uint256 expiresAt;         // Auto-refund deadline
  uint256 depositedTotal;    // amount * 2
}
```

---

## 🔑 Environment Variables

**Required for all features:**

```bash
# Firebase (in google-services.json / GoogleService-Info.plist)
# - No manual env vars needed, auto-configured

# Arc Testnet (in lib/config.dart)
ARC_RPC_URL=https://testnet.rpc.arc.io
ESCROW_CONTRACT_ADDRESS=0x1234567890123456789012345678901234567890
USDC_TOKEN_ADDRESS=0x0000000000000000000000000000000000000001

# Cloud Function Operator (Firebase Secret Manager)
OPERATOR_PRIVATE_KEY=0x... (KEEP PRIVATE!)
```

---

## 🧪 Testing Checklist

### Before Committing

```bash
# Static analysis
flutter analyze

# Format code
dart format lib/ contracts/ functions/

# Run tests (if any)
flutter test

# Build APK/IPA
flutter build apk
flutter build ios
```

### Offline Testing
- [ ] Play single game, verify win/loss/draw
- [ ] Test all win conditions (rows, cols, diagonals)
- [ ] Verify move rate limiting (500ms)
- [ ] Test reset button

### Online Testing (Firebase)
- [ ] Create 2+ accounts
- [ ] Join match, sync board
- [ ] Verify opponent's moves appear in real-time
- [ ] Complete game, verify ELO updates
- [ ] Check Firebase Database for match record

### Betting Testing (Arc Testnet)
- [ ] Connect MetaMask to Arc testnet
- [ ] Request test ETH + USDC from faucet
- [ ] Approve USDC to escrow contract
- [ ] Place bet with test USDC
- [ ] Opponent joins & deposits
- [ ] Play game, verify Cloud Function validates
- [ ] Check wallet for payout + fee

---

## 🐛 Debugging Tips

### Flutter App Crashes
```bash
# View logs
flutter logs

# Debug prints
print('Debug: $variable');

# Use DevTools
flutter pub global activate devtools
devtools

# Or from VS Code: Run → Start Debugging
```

### Firebase Issues
```bash
# Check Firebase Console
# - Authentication: Verify anonymous login enabled
# - Realtime Database: Check rules & data structure
# - Cloud Functions: View logs in Console

# CLI debugging
firebase emulator:start  # Local emulation
firebase debug-logging  # Enable verbose logs
```

### Contract Issues
```bash
# Check transaction on Arc block explorer
# https://testnet.explorer.arc.io/tx/0x...

# Verify contract address
# https://testnet.explorer.arc.io/address/0x...

# Remix debugging
# - Open contract in Remix
# - Check Events for transaction receipt
# - View state variables
```

### ERC20 Token Issues
```bash
# Check token balance
web3.eth.call({
  to: usdcTokenAddress,
  data: balanceOf(userAddress)
});

# Check allowance
web3.eth.call({
  to: usdcTokenAddress,
  data: allowance(userAddress, escrowAddress)
});
```

---

## 📈 Performance Considerations

| Component | Metric | Target |
|-----------|--------|--------|
| Offline game load | < 100ms | ✅ |
| Firebase sync | < 500ms | ✅ |
| Opponent move latency | < 2s | ✅ |
| ELO calculation | < 1s | ✅ |
| Wallet connect | < 5s | ✅ |
| USDC approve tx | < 30s | ✅ (network dependent) |

**Optimization strategies:**
- Cache user ratings locally
- Batch Firebase writes
- Pre-load contract ABIs
- Implement request debouncing
- Use transaction pooling

---

## 🔒 Security Checklist

- [ ] No private keys in version control
- [ ] WalletConnect bridge trusted (use official)
- [ ] ERC20 safe transfer wrapper used
- [ ] Re-entrancy guards on contract
- [ ] CEI pattern in sensitive functions
- [ ] Input validation on all user inputs
- [ ] Rate limiting on matchmaking
- [ ] HTTPS for all external calls
- [ ] Firebase rules restrict unauthorized access
- [ ] Cloud Function validates all match data

---

## 🚢 Deployment Steps

### Testnet (Current)
1. Deploy Escrow.sol to Arc testnet
2. Test with testnet USDC
3. Gather user feedback
4. Fix bugs & optimize

### Mainnet (Future)
1. Formal security audit
2. Extended testnet period
3. Deploy to Arc mainnet with real USDC
4. Announce on social media
5. Monitor for issues

---

## 📞 Support & Resources

### Documentation
- [README.md](README.md) - Project overview
- [GAME_RULES.md](GAME_RULES.md) - Game spec
- [MULTIPLAYER_IMPLEMENTATION.md](MULTIPLAYER_IMPLEMENTATION.md) - Tech architecture
- [contracts/ARC_ESCROW_DEPLOYMENT.md](contracts/ARC_ESCROW_DEPLOYMENT.md) - Deployment guide

### External Links
- **GitHub Issues:** https://github.com/NexsisNelson/ArcTicTac/issues
- **Flutter Docs:** https://flutter.dev/docs
- **Firebase Docs:** https://firebase.google.com/docs
- **Solidity Docs:** https://docs.soliditylang.org
- **Arc Network:** https://docs.arc.io

### Team Contacts
- **Project Lead:** [Your Name] - lead@arctictac.example
- **Backend Engineer:** [Backend Dev] - backend@arctictac.example
- **Smart Contract Auditor:** [Auditor] - audit@arctictac.example

---

## 🎉 Congratulations!

You now have everything needed to contribute to Arc TicTac! 

**Next steps:**
1. Pick a task from GitHub Issues
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Implement & test
4. Push & create PR
5. Await review & merge

**Happy coding!** 🚀
