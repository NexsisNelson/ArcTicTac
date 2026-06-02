# TicTacToe Arc (Testnet)

Minimal Flutter TicTacToe app with **offline**, **online multiplayer (Firebase)**, and **Arc blockchain USDC betting** integration.

**Features:**
- ✅ Offline 3x3 TicTacToe with local AI
- ✅ Online multiplayer with ELO-based matchmaking (Firebase)
- ✅ Real-time move synchronization
- ✅ USDC betting on Arc testnet via smart contract escrow
- ✅ Wallet authentication (WalletConnect)
- ✅ Non-custodial bet management (operator-based resolution)

---

## Quick Start

### Prerequisites
- Flutter SDK 2.18.0+
- Dart 2.18.0+
- Firebase project (for online multiplayer)
- Arc testnet wallet (MetaMask) with test ETH + USDC (for betting)

### Setup

1. **Clone the repository:**
```bash
git clone https://github.com/NexsisNelson/ArcTicTac.git
cd ArcTicTac
```

2. **Install Flutter dependencies:**
```bash
flutter pub get
```

3. **Run the app:**
```bash
flutter run
```

---

## Firebase Setup (Required for Online Multiplayer)

1. Create a Firebase project at https://console.firebase.google.com/
2. Add an Android and/or iOS app to the project and follow platform setup steps:
   - Download `google-services.json` (Android) or `GoogleService-Info.plist` (iOS)
   - Place in platform-specific directories (`android/app/`, `ios/Runner/`)
3. Enable **Authentication** → **Sign-in method** → **Anonymous**
4. Create **Realtime Database** with development rules:

```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

5. Deploy Cloud Function for match validation (see below)

---

## Arc Testnet & Smart Contract Setup

### 1. **Configure Arc Testnet in MetaMask**

| Field | Value |
|-------|-------|
| Network Name | Arc Testnet |
| RPC URL | https://testnet.rpc.arc.io |
| Chain ID | 42 |
| Currency | ETH |
| Block Explorer | https://testnet.explorer.arc.io |

### 2. **Get Testnet Funds**

- Request testnet ETH + USDC from https://testnet-faucet.arc.io

### 3. **Deploy Escrow Contract**

See **[contracts/ARC_ESCROW_DEPLOYMENT.md](contracts/ARC_ESCROW_DEPLOYMENT.md)** for:
- Remix deployment (easy, browser-based)
- Hardhat deployment (recommended for production)
- Contract verification on block explorer

**Quick Remix Deploy:**
```
1. Visit https://remix.ethereum.org
2. Create new file: Escrow.sol
3. Copy contents from contracts/Escrow.sol
4. Compile with version ^0.8.19
5. Connect MetaMask to Arc testnet
6. Deploy with constructor args:
   - _operator: 0x... (Cloud Function signer, or your address for testing)
   - _treasury: 0x... (fee recipient)
   - _feeBps: 200 (2%)
7. Save contract address (needed in Flutter config)
```

### 4. **Configure Flutter App**

Create or update `lib/config.dart`:

```dart
const String arcRpcUrl = 'https://testnet.rpc.arc.io';
const String escrowContractAddress = '0x1234567890123456789012345678901234567890'; // From Remix
const String usdcTokenAddress = '0x0000000000000000000000000000000000000001'; // Arc testnet USDC
const int minBetUsdc = 1;
const int maxBetUsdc = 1000;
const int feeBps = 200; // 2%
```

---

## Cloud Function Setup (Match Validation)

### Install Firebase CLI

```bash
npm install -g firebase-tools
firebase login
```

### Deploy Function

```bash
cd functions
npm install
firebase deploy --only functions
```

The function:
- ✅ Validates final game board (win detection, move sequence)
- ✅ Computes ELO ratings and updates Firebase
- ✅ Calls escrow contract to resolve bets (if betting enabled)

---

## Betting Flow

### Player A: Initiates Bet

1. Click **"Play Online"** → **"Place Bet"**
2. Enter bet amount (1–1000 USDC)
3. Select opponent or wait for matchmaking
4. **Create Match:**
   - App calls `escrowService.createMatch()` → returns `matchId`
5. **Approve USDC:**
   - App calls `escrowService.approveUsdc(amount)`
   - Wallet signs transaction
6. **Deposit Bet:**
   - App calls `escrowService.deposit(matchId)`
   - Escrow contract receives USDC (match status: **Waiting** → **Funded**)
7. Wait for opponent

### Player B: Accepts Bet

1. See waiting match in queue
2. Click **"Join"**
3. Same approve + deposit flow
4. Once both deposited: Match status = **Playing** ✅

### Game Play

1. Real-time Firebase sync (no blockchain interaction)
2. Normal game logic applies
3. Win/draw/forfeit determined locally

### Match Resolution

1. Game ends → Firebase records winner
2. Cloud Function validates board
3. Operator calls `escrowContract.resolveMatch(matchId, winner)`
4. Escrow transfers:
   - **Winner:** `(betAmount × 2) - 2% fee`
   - **Treasury:** `2% fee`
5. Match status = **Resolved** ✅
6. UI shows transaction hash + payout

---

## Architecture

### File Structure

```
lib/
├── main.dart                 # Main app UI, game screens
├── wallet_service.dart       # WalletConnect integration
├── escrow_service.dart       # Smart contract interaction (Web3)
└── config.dart              # Configuration constants

contracts/
├── Escrow.sol               # Non-custodial escrow contract
├── ESCROW_DESIGN.md         # Design & security rationale
└── ARC_ESCROW_DEPLOYMENT.md # Deployment & integration guide

functions/
├── src/index.ts             # Cloud Function (match validation & ELO)
└── package.json             # Dependencies

documentation/
├── GAME_RULES.md            # Complete game specification
├── UI_UX_DESIGN.md          # UI mockups & interaction flows
└── MULTIPLAYER_IMPLEMENTATION.md  # Technical architecture
```

### Key Technologies

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | Flutter/Dart | Cross-platform mobile UI |
| **Online Sync** | Firebase Realtime DB | Match state & opponent tracking |
| **Validation** | Cloud Functions (Node.js) | Server-side board verification |
| **Blockchain** | Arc testnet (EVM) | USDC betting & escrow |
| **Web3** | web3dart, WalletConnect | Wallet interaction & contract calls |
| **Escrow** | Solidity ^0.8.19 | Non-custodial bet management |

---

## Configuration & Secrets

### Environment Variables (.env)

```env
# Arc Testnet
ARC_RPC_URL=https://testnet.rpc.arc.io
ARC_CHAIN_ID=42

# Contracts
ESCROW_CONTRACT_ADDRESS=0x...
USDC_TOKEN_ADDRESS=0x...

# Operator (Cloud Function signer - keep private!)
OPERATOR_PRIVATE_KEY=0x...

# Firebase
FIREBASE_PROJECT_ID=your-project-id
```

⚠️ **NEVER commit `.env` or private keys to git!** Use:
```bash
git update-index --assume-unchanged .env
```

---

## Testing

### Offline Mode (No Setup Required)

```bash
flutter run
# Select "Offline" → Play game locally
```

### Online Multiplayer (Firebase Required)

```bash
flutter run
# Select "Online" → Sign in anonymously → Matchmaking
```

### Betting on Arc (Full Stack)

1. Deploy contract to Arc testnet (see above)
2. Configure `lib/config.dart` with contract address
3. Request test USDC from faucet
4. In-app: Click **"Place Bet"** → Wallet signatures → Game → Resolution

### Contract Testing

```bash
# Remix (Browser)
# - Open Remix IDE
# - Load Escrow.sol
# - Deploy with test args
# - Call functions directly

# Or use Hardhat
cd contracts
npm install hardhat @nomicfoundation/hardhat-toolbox
npx hardhat init
# ... configure Arc testnet ...
npx hardhat run scripts/deploy.js --network arc
```

---

## Security Notes

### ⚠️ Private Key Management

**Never embed private keys in the Flutter app!** Use one of:

1. **WalletConnect (Recommended)**
   - User's wallet signs transactions
   - Private key stays in wallet app
   - No key exposure in Flutter

2. **Secure Storage + User PIN**
   - Encrypt private key with device secure storage
   - Decrypt only when signing transactions
   - Requires additional setup

3. **Backend Signer (Operator)**
   - Backend (Cloud Function) signs escrow resolutions
   - User signs game moves/message (EIP-712)
   - Reduces app responsibility

### Contract Security

✅ **Implemented:**
- Re-entrancy guards (nonReentrant modifier)
- Checks-Effects-Interactions (CEI) pattern
- Operator validation (match resolution)
- Fee caps (max 5%)
- Safe ERC20 transfer wrapper

**Before Mainnet:**
- [ ] Formal audit by security firm
- [ ] Extended testnet period
- [ ] Bug bounty program
- [ ] Rate limiting on resolutions

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Flutter SDK not found" | Install Flutter: https://flutter.dev/docs/get-started/install |
| "Dependency conflict" | Run `flutter pub get` and check `pubspec.yaml` versions |
| "Firebase not connecting" | Ensure `google-services.json` / `GoogleService-Info.plist` in correct directories |
| "MetaMask not connecting" | Ensure Arc testnet added to wallet; check WalletConnect bridge |
| "USDC approve fails" | Check balance > bet amount; verify token address on testnet |
| "Match not funded" | Both players must call `deposit()` and receive confirmation |
| "Transaction reverted" | Check escrow contract status; verify operator is calling `resolveMatch()` |

---

## Next Steps

1. ✅ **Deploy contract** to Arc testnet
2. ✅ **Test betting flow** with testnet USDC
3. ⏳ **Leaderboard integration** (persistent ranking)
4. ⏳ **Spectate mode** (watch ongoing matches)
5. ⏳ **Mainnet migration** (deploy to Arc mainnet with real USDC)
6. ⏳ **Mobile app stores** (iOS App Store, Google Play)

---

## Resources

- **Flutter Docs:** https://flutter.dev/docs
- **Firebase Docs:** https://firebase.google.com/docs
- **Web3dart:** https://pub.dev/packages/web3dart
- **Solidity Docs:** https://docs.soliditylang.org
- **Arc Network:** https://docs.arc.io
- **Remix IDE:** https://remix.ethereum.org

---

## License

MIT License - See LICENSE file

---

## Support

For issues or questions:
- **GitHub Issues:** https://github.com/NexsisNelson/ArcTicTac/issues
- **Discord:** [Community Server]
- **Email:** support@arctictac.example

---

## Deployment Checklist

- [ ] Firebase project created & configured
- [ ] Cloud Functions deployed
- [ ] Arc testnet contract deployed
- [ ] Flutter app configured with contract address
- [ ] Wallet integration tested
- [ ] USDC betting flow tested
- [ ] ELO system verified
- [ ] Move validation working
- [ ] Match resolution working
- [ ] Ready for UAT

---

**Status:** 🚀 Testnet Ready | ⏳ Mainnet Pending

