# Arc Testnet Escrow Deployment & Integration Guide

## Overview

This guide covers deploying the `TicTacToeEscrow.sol` contract on Arc testnet, configuring it for USDC betting, and integrating it with the Flutter app for placing and resolving bets.

---

## Part 1: Escrow Contract Architecture

### Contract Structure

```solidity
TicTacToeEscrow
├── Match Management
│   ├── createMatch()
│   ├── deposit()
│   └── joinMatch()
├── Resolution
│   ├── resolveMatch() [operator only]
│   └── refundMatch()
├── Admin
│   ├── setOperator()
│   ├── setFeeBps()
│   ├── setTreasury()
│   └── emergencyWithdraw()
└── Views
    ├── getMatch()
    └── isMatchFunded()
```

### Key Security Features

1. **Re-entrancy Protection** (`nonReentrant` modifier)
   - Prevents nested calls to sensitive functions
   - Uses simple guard pattern (locked flag)

2. **Checks-Effects-Interactions (CEI) Pattern**
   - State updates before external calls
   - Reduces risk from malicious token re-entrancy

3. **Safe Transfer Wrapper**
   - Handles both ERC20 return types (bool or void)
   - Gracefully handles non-standard tokens

4. **Operator Model**
   - Only operator can resolve matches (calls from Cloud Function)
   - Reduces gas costs vs. on-chain validation
   - Operator key stored securely (not in Flutter app)

---

## Part 2: Arc Testnet Setup

### Prerequisites

1. **MetaMask / Wallet**
   - Download [MetaMask](https://metamask.io)
   - Create or import account

2. **Arc Testnet Configuration**
   - Network Name: `Arc Testnet`
   - RPC URL: `https://testnet.rpc.arc.io` (or your provider's URL)
   - Chain ID: `Arc_Testnet_ChainID` (typically `42` or similar)
   - Currency Symbol: `ETH` or `AARC`
   - Block Explorer: `https://testnet.explorer.arc.io`

3. **Test USDC Token**
   - Arc testnet usually has a test USDC token pre-deployed
   - Contract Address: `0x...` (verify via Arc docs)
   - Request faucet funds for testing

### MetaMask Setup Steps

```
1. Open MetaMask
2. Click "Add Network" (top-right menu)
3. Enter Arc testnet details:
   - Network Name: Arc Testnet
   - RPC URL: https://testnet.rpc.arc.io
   - Chain ID: 42 (or correct ID)
   - Currency: ETH
   - Block Explorer: https://testnet.explorer.arc.io
4. Save
5. Request testnet ETH and USDC from faucet
```

---

## Part 3: Escrow Contract Deployment

### Option A: Using Remix IDE (Easy)

```
1. Visit https://remix.ethereum.org
2. Create new file: Escrow.sol
3. Copy contracts/Escrow.sol code
4. In Solidity Compiler tab:
   - Select version ^0.8.19
   - Enable optimization (runs: 200)
   - Compile
5. In Deploy tab:
   - Connect MetaMask to Arc testnet
   - Select "TicTacToeEscrow" contract
   - Constructor args:
     * _operator: 0x... (Cloud Function signer address)
     * _treasury: 0x... (fee recipient)
     * _feeBps: 200 (2% fee)
   - Deploy
6. Verify contract address
```

### Option B: Using Hardhat (Recommended for Production)

```bash
# Create hardhat project
npx hardhat init

# Install Arc plugin
npm install @arc-network/hardhat-plugin

# Create deploy script (scripts/deploy.js)
async function main() {
  const [deployer] = await ethers.getSigners();
  const operatorAddress = "0x..."; // Cloud Function signer
  const treasuryAddress = deployer.address;
  const feeBps = 200; // 2%

  const TicTacToeEscrow = await ethers.getContractFactory("TicTacToeEscrow");
  const escrow = await TicTacToeEscrow.deploy(
    operatorAddress,
    treasuryAddress,
    feeBps
  );
  
  await escrow.deployed();
  console.log("Escrow deployed to:", escrow.address);
}

main().catch(console.error);

# Deploy
npx hardhat run scripts/deploy.js --network arc-testnet
```

### Deployment Output Example

```
Escrow deployed to: 0x1234567890123456789012345678901234567890
```

**Save this address!** You'll need it in Flutter app configuration.

---

## Part 4: Configuration

### Environment Variables

Create `.env` file in project root:

```env
# Arc Testnet RPC
ARC_RPC_URL=https://testnet.rpc.arc.io
ARC_CHAIN_ID=42

# Contract Addresses
ESCROW_CONTRACT_ADDRESS=0x1234567890123456789012345678901234567890
USDC_TOKEN_ADDRESS=0x0000000000000000000000000000000000000001

# Operator (Cloud Function signer)
OPERATOR_ADDRESS=0x...

# Treasury (fee recipient)
TREASURY_ADDRESS=0x...

# WalletConnect Project ID
WALLET_CONNECT_PROJECT_ID=your_project_id_here
```

### Flutter pubspec.yaml Updates

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.32.0
  firebase_auth: ^4.6.0
  firebase_database: ^10.0.0
  web3dart: ^2.5.0
  walletconnect_dart: ^0.0.11
  url_launcher: ^6.1.10
  http: ^0.13.6
```

---

## Part 5: Flutter Integration

### Configuration Constants (lib/config.dart)

```dart
const String arcRpcUrl = 'https://testnet.rpc.arc.io';
const String escrowContractAddress = '0x1234567890123456789012345678901234567890';
const String usdcTokenAddress = '0x0000000000000000000000000000000000000001';
const int minBetUsdc = 1; // 1 USDC minimum
const int maxBetUsdc = 1000; // 1000 USDC maximum
const int feeBps = 200; // 2% fee
```

### Escrow Service Class (lib/escrow_service.dart)

```dart
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';

class EscrowService {
  final String rpcUrl;
  final String escrowAddress;
  final String usdcAddress;
  
  late Web3Client client;
  late DeployedContract escrowContract;
  
  EscrowService({
    required this.rpcUrl,
    required this.escrowAddress,
    required this.usdcAddress,
  });
  
  Future<void> init() async {
    client = Web3Client(rpcUrl, Client());
    final abi = ContractAbi.fromJson(escrowAbi, 'TicTacToeEscrow');
    escrowContract = DeployedContract(
      abi,
      EthereumAddress.fromHex(escrowAddress),
    );
  }
  
  /// Create a new betting match
  /// Returns matchId
  Future<String> createMatch({
    required String player2Address,
    required BigInt betAmount,
    required int secondsTimeout,
    required String senderPrivateKey,
  }) async {
    final expiresAt = BigInt.from(
      DateTime.now().add(Duration(seconds: secondsTimeout)).millisecondsSinceEpoch ~/ 1000,
    );
    
    final createMatchFn = escrowContract.function('createMatch');
    final transaction = Transaction.callContract(
      contract: escrowContract,
      function: createMatchFn,
      parameters: [
        EthereumAddress.fromHex(player2Address),
        EthereumAddress.fromHex(usdcAddress),
        betAmount,
        expiresAt,
      ],
    );
    
    // Sign and send transaction
    final txHash = await client.sendTransaction(
      EthereumPrivateKey.fromHex(senderPrivateKey),
      transaction,
      chainId: 42, // Arc testnet chain ID
    );
    
    return txHash;
  }
  
  /// Approve USDC spending by escrow contract
  Future<String> approveUsdc({
    required BigInt amount,
    required String senderPrivateKey,
  }) async {
    final erc20Abi = ContractAbi.fromJson(erc20AbiJson, 'ERC20');
    final usdc = DeployedContract(erc20Abi, EthereumAddress.fromHex(usdcAddress));
    
    final approveFn = usdc.function('approve');
    final transaction = Transaction.callContract(
      contract: usdc,
      function: approveFn,
      parameters: [
        EthereumAddress.fromHex(escrowAddress),
        amount,
      ],
    );
    
    final txHash = await client.sendTransaction(
      EthereumPrivateKey.fromHex(senderPrivateKey),
      transaction,
      chainId: 42,
    );
    
    return txHash;
  }
  
  /// Deposit USDC stake into escrow
  Future<String> deposit({
    required int matchId,
    required String senderPrivateKey,
  }) async {
    final depositFn = escrowContract.function('deposit');
    final transaction = Transaction.callContract(
      contract: escrowContract,
      function: depositFn,
      parameters: [BigInt.from(matchId)],
    );
    
    final txHash = await client.sendTransaction(
      EthereumPrivateKey.fromHex(senderPrivateKey),
      transaction,
      chainId: 42,
    );
    
    return txHash;
  }
  
  /// Get match details
  Future<Map<String, dynamic>> getMatch(int matchId) async {
    final getMatchFn = escrowContract.function('getMatch');
    final result = await client.call(
      contract: escrowContract,
      function: getMatchFn,
      params: [BigInt.from(matchId)],
    );
    
    return {
      'player1': result[0],
      'player2': result[1],
      'amount': result[3] as BigInt,
      'status': result[6], // 0=Waiting, 1=Funded, 2=Playing, 3=Resolved, 4=Cancelled
    };
  }
  
  /// Check if match is funded
  Future<bool> isMatchFunded(int matchId) async {
    final isFundedFn = escrowContract.function('isMatchFunded');
    final result = await client.call(
      contract: escrowContract,
      function: isFundedFn,
      params: [BigInt.from(matchId)],
    );
    
    return result.first as bool;
  }
}

// ABI snippets (in constants file)
const String escrowAbi = '''[...]'''; // Full ABI from Remix
const String erc20AbiJson = '''[...]'''; // Standard ERC20 ABI
```

---

## Part 6: Cloud Function Integration

### Cloud Function: Resolve Match

```typescript
import * as functions from 'firebase-functions';
import { ethers } from 'ethers';

const escrowAddress = '0x1234567890123456789012345678901234567890';
const provider = new ethers.providers.JsonRpcProvider('https://testnet.rpc.arc.io');
const operatorSigner = new ethers.Wallet(
  process.env.OPERATOR_PRIVATE_KEY!,
  provider,
);

const escrowContract = new ethers.Contract(
  escrowAddress,
  ESCROW_ABI,
  operatorSigner,
);

export const resolveMatch = functions.https.onCall(async (data, context) => {
  const { matchId, winner, board, status } = data;

  // Validate game result (Cloud Function validation)
  const isValid = validateBoard(board, status);
  if (!isValid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Board validation failed',
    );
  }

  // Call escrow contract to resolve
  const tx = await escrowContract.resolveMatch(matchId, winner);
  const receipt = await tx.wait();

  return {
    success: true,
    transactionHash: receipt.transactionHash,
    gasUsed: receipt.gasUsed.toString(),
  };
});

function validateBoard(board: string[], status: string): boolean {
  // Verify winning condition
  // Check move sequence validity
  // Return true if valid
  return true; // placeholder
}
```

---

## Part 7: Betting Flow Walkthrough

### Flow Diagram

```
1. Player A initiates bet (amount, opponent)
   ↓
2. Creates match in escrow contract
   ├─ createMatch(player2, USDC, amount, expires_at)
   └─ Returns matchId
   ↓
3. Player A approves USDC spending
   ├─ approve(escrowAddress, amount)
   ├─ Transaction confirmed
   └─ Allowance set
   ↓
4. Player A deposits into escrow
   ├─ deposit(matchId)
   ├─ Transfers amount to escrow contract
   └─ Match status: Waiting → Funded (when both deposited)
   ↓
5. Player B joins match & deposits
   ├─ Sees match in queue
   ├─ Approves USDC
   ├─ Calls deposit(matchId)
   └─ Match status: Funded → Playing
   ↓
6. Game plays normally (real-time Firebase sync)
   ├─ Moves sync via Firebase
   ├─ Game logic validates locally
   └─ No blockchain interaction during play
   ↓
7. Game ends (win/draw/forfeit)
   ├─ Firebase records final status
   ├─ Cloud Function validates board
   └─ Operator calls resolveMatch()
   ↓
8. Escrow resolves
   ├─ Transfers winner payout (amount × 2 - fee)
   ├─ Transfers fee to treasury (2%)
   └─ Match status: Playing → Resolved
   ↓
9. UI shows results
   ├─ Winner amount received
   ├─ Transaction hash displayed
   └─ Return to menu
```

### Code Example: Placing a Bet

```dart
// In Flutter app, when user clicks "Place Bet" button

Future<void> _placeBet(BigInt betAmount, String opponentAddress) async {
  try {
    // 1. Create match in escrow
    final createTx = await _escrowService.createMatch(
      player2Address: opponentAddress,
      betAmount: betAmount,
      secondsTimeout: 300, // 5 minutes
      senderPrivateKey: _userPrivateKey,
    );
    print('Match created: $createTx');

    // Wait for confirmation
    await _waitForTxConfirmation(createTx);

    // 2. Approve USDC if needed
    if (_usdcAllowance < betAmount) {
      final approveTx = await _escrowService.approveUsdc(
        amount: betAmount,
        senderPrivateKey: _userPrivateKey,
      );
      await _waitForTxConfirmation(approveTx);
    }

    // 3. Deposit into escrow
    final depositTx = await _escrowService.deposit(
      matchId: matchId,
      senderPrivateKey: _userPrivateKey,
    );
    await _waitForTxConfirmation(depositTx);

    // Show success
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bet placed! Waiting for opponent...')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bet failed: $e')),
    );
  }
}
```

---

## Part 8: Testing Checklist

### Unit Tests

- [ ] createMatch: Valid/invalid parameters
- [ ] deposit: Both players, double-deposit rejection
- [ ] resolveMatch: Valid/invalid winner, fee calculation
- [ ] refundMatch: Expired matches, refund logic
- [ ] Re-entrancy: No nested calls allowed

### Integration Tests (Arc Testnet)

- [ ] Deploy contract successfully
- [ ] Create match with test addresses
- [ ] Approve USDC spending
- [ ] Deposit both players
- [ ] Verify match transitions (Waiting → Funded → Playing)
- [ ] Resolve match with correct payout
- [ ] Verify fee goes to treasury
- [ ] Refund expired match
- [ ] Test emergency withdrawal (owner only)

### End-to-End (Flutter + Escrow)

- [ ] Connect wallet (MetaMask)
- [ ] Check USDC balance
- [ ] Place bet in Flutter app
- [ ] Play game (Firebase sync works)
- [ ] Game ends, Cloud Function resolves
- [ ] Check wallet for USDC payout
- [ ] Verify transaction on Arc block explorer

---

## Part 9: Security Considerations

### Private Key Management

⚠️ **CRITICAL**: Never hardcode private keys in app or version control.

**Safe Approaches:**

1. **User-Controlled Private Key** (Recommended)
   - User imports private key via WalletConnect
   - Private key never stored locally
   - Transactions signed by wallet app

2. **Encrypted Local Storage** (Advanced)
   - Encrypt private key with user's PIN
   - Store encrypted in device secure storage
   - Decrypt only for signing transactions

3. **Cloud Function Signer** (Backend-only)
   - Backend (Cloud Function) signs transactions
   - Escrow contract calls are operator-only
   - Player provides signatures via message signing (SIWE)

### Operator Key Security

The operator private key (for Cloud Function) should be:

- Stored in **Firebase Secret Manager** or **Secrets Vault**
- Rotatable
- Audited logs (all resolveMatch calls)
- Separate from application secrets

### Contract Audit

Before mainnet deployment:

- [ ] Code review by auditor
- [ ] Static analysis (Slither, MythX)
- [ ] Formal verification (optional)
- [ ] Extended testnet period
- [ ] Bug bounty program

---

## Part 10: Deployment Checklist

### Pre-Deployment

- [ ] Contract code reviewed
- [ ] ABI saved and tested
- [ ] Environment variables configured
- [ ] Operator key secured
- [ ] RPC endpoint verified
- [ ] USDC token address confirmed on testnet

### Deployment Steps

1. Deploy contract to Arc testnet
2. Verify contract on block explorer
3. Configure Flutter app with contract address
4. Test full betting flow
5. Deploy Cloud Function with operator signer
6. Test match resolution
7. Set up monitoring & alerting

### Post-Deployment

- [ ] Monitor contract for issues
- [ ] Track gas costs
- [ ] Audit transaction logs
- [ ] Gather user feedback
- [ ] Document any bugs
- [ ] Plan mainnet migration

---

## Appendix: Useful Arc Testnet Resources

- **Testnet Explorer**: https://testnet.explorer.arc.io
- **Testnet Faucet**: https://testnet-faucet.arc.io
- **RPC Endpoint**: https://testnet.rpc.arc.io
- **Documentation**: https://docs.arc.io
- **Discord Support**: https://discord.gg/arc

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Insufficient USDC balance" | Request more testnet USDC from faucet |
| "Transaction reverted" | Check allowance, balance, or match status |
| "Invalid operator" | Verify operator address in contract |
| "Gas estimation failed" | Check RPC connection, increase gas price |
| "Wallet not connected" | Reconnect MetaMask to Arc testnet |

---

## Next Steps

1. Deploy contract to Arc testnet
2. Test with test accounts
3. Integrate with Flutter app
4. Deploy Cloud Function
5. End-to-end testing
6. User acceptance testing (UAT)
7. Mainnet preparation
