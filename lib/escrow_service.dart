import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';

/// Service for interacting with Arc TicTacToeEscrow smart contract
class EscrowService {
  final String rpcUrl;
  final String escrowAddress;
  final String usdcAddress;
  final int chainId; // Arc testnet chain ID (usually 42 or similar)

  late Web3Client _client;
  late DeployedContract _escrowContract;
  late DeployedContract _usdcContract;

  EscrowService({
    required this.rpcUrl,
    required this.escrowAddress,
    required this.usdcAddress,
    this.chainId = 42, // Arc testnet
  });

  /// Initialize the service - must be called before using other methods
  Future<void> init() async {
    _client = Web3Client(rpcUrl, Client());

    // Load escrow contract
    final escrowAbi = ContractAbi.fromJson(
      _getEscrowAbi(),
      'TicTacToeEscrow',
    );
    _escrowContract = DeployedContract(
      escrowAbi,
      EthereumAddress.fromHex(escrowAddress),
    );

    // Load USDC contract
    final erc20Abi = ContractAbi.fromJson(_getErc20Abi(), 'ERC20');
    _usdcContract = DeployedContract(
      erc20Abi,
      EthereumAddress.fromHex(usdcAddress),
    );
  }

  /// Create a new betting match
  /// Returns transaction hash
  Future<String> createMatch({
    required String player2Address,
    required BigInt betAmountInWei,
    required int durationSeconds,
    required String senderPrivateKey,
  }) async {
    try {
      final expiresAt = BigInt.from(
        DateTime.now()
                .add(Duration(seconds: durationSeconds))
                .millisecondsSinceEpoch ~/
            1000,
      );

      final createMatchFunction = _escrowContract.function('createMatch');
      final transaction = Transaction.callContract(
        contract: _escrowContract,
        function: createMatchFunction,
        parameters: [
          EthereumAddress.fromHex(player2Address),
          EthereumAddress.fromHex(usdcAddress),
          betAmountInWei,
          expiresAt,
        ],
        maxGas: 300000,
      );

      final credentials = EthPrivateKey.fromHex(senderPrivateKey);
      final txHash = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );

      return txHash;
    } catch (e) {
      throw Exception('Failed to create match: $e');
    }
  }

  /// Approve USDC token spending by escrow contract
  /// Returns transaction hash
  Future<String> approveUsdc({
    required BigInt amountInWei,
    required String senderPrivateKey,
  }) async {
    try {
      final approveFunction = _usdcContract.function('approve');
      final transaction = Transaction.callContract(
        contract: _usdcContract,
        function: approveFunction,
        parameters: [
          EthereumAddress.fromHex(escrowAddress),
          amountInWei,
        ],
        maxGas: 100000,
      );

      final credentials = EthPrivateKey.fromHex(senderPrivateKey);
      final txHash = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );

      return txHash;
    } catch (e) {
      throw Exception('Failed to approve USDC: $e');
    }
  }

  /// Deposit USDC stake into escrow match
  /// Returns transaction hash
  Future<String> deposit({
    required BigInt matchId,
    required String senderPrivateKey,
  }) async {
    try {
      final depositFunction = _escrowContract.function('deposit');
      final transaction = Transaction.callContract(
        contract: _escrowContract,
        function: depositFunction,
        parameters: [matchId],
        maxGas: 200000,
      );

      final credentials = EthPrivateKey.fromHex(senderPrivateKey);
      final txHash = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );

      return txHash;
    } catch (e) {
      throw Exception('Failed to deposit: $e');
    }
  }

  /// Get USDC allowance for escrow contract
  Future<BigInt> getUsdcAllowance({required String ownerAddress}) async {
    try {
      final allowanceFunction = _usdcContract.function('allowance');
      final result = await _client.call(
        contract: _usdcContract,
        function: allowanceFunction,
        params: [
          EthereumAddress.fromHex(ownerAddress),
          EthereumAddress.fromHex(escrowAddress),
        ],
      );

      return result.first as BigInt;
    } catch (e) {
      throw Exception('Failed to get USDC allowance: $e');
    }
  }

  /// Get USDC balance for an address
  Future<BigInt> getUsdcBalance({required String address}) async {
    try {
      final balanceOfFunction = _usdcContract.function('balanceOf');
      final result = await _client.call(
        contract: _usdcContract,
        function: balanceOfFunction,
        params: [EthereumAddress.fromHex(address)],
      );

      return result.first as BigInt;
    } catch (e) {
      throw Exception('Failed to get USDC balance: $e');
    }
  }

  /// Get match details from escrow contract
  Future<Map<String, dynamic>> getMatch({required BigInt matchId}) async {
    try {
      final getMatchFunction = _escrowContract.function('getMatch');
      final result = await _client.call(
        contract: _escrowContract,
        function: getMatchFunction,
        params: [matchId],
      );

      // Parse Match struct result
      final match = result.first as List<dynamic>;
      return {
        'player1': match[0].toString(),
        'player2': match[1].toString(),
        'token': match[2].toString(),
        'amount': match[3] as BigInt,
        'p1Deposited': match[4] as bool,
        'p2Deposited': match[5] as bool,
        'status': match[6]
            as int, // 0=Waiting, 1=Funded, 2=Playing, 3=Resolved, 4=Cancelled
        'createdAt': match[7] as BigInt,
        'expiresAt': match[8] as BigInt,
        'depositedTotal': match[9] as BigInt,
      };
    } catch (e) {
      throw Exception('Failed to get match: $e');
    }
  }

  /// Check if a match is funded (both players deposited)
  Future<bool> isMatchFunded({required BigInt matchId}) async {
    try {
      final isFundedFunction = _escrowContract.function('isMatchFunded');
      final result = await _client.call(
        contract: _escrowContract,
        function: isFundedFunction,
        params: [matchId],
      );

      return result.first as bool;
    } catch (e) {
      throw Exception('Failed to check if match is funded: $e');
    }
  }

  /// Check transaction receipt status
  /// Returns null if transaction still pending or not found
  Future<bool?> checkTransactionStatus({required String txHash}) async {
    try {
      final receipt = await _client.getTransactionReceipt(txHash);
      if (receipt == null) return null; // Transaction not yet mined

      // receipt.status is null on some networks, check for events instead
      return receipt.status ?? true; // Default to success if status unavailable
    } catch (e) {
      throw Exception('Failed to check transaction status: $e');
    }
  }

  /// Wait for a transaction receipt and return it (or null if timeout)
  Future<TransactionReceipt?> waitForTransactionReceipt(String txHash,
      {Duration timeout = const Duration(minutes: 5),
      Duration pollInterval = const Duration(seconds: 3)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final receipt = await _client.getTransactionReceipt(txHash);
      if (receipt != null) return receipt;
      await Future.delayed(pollInterval);
    }
    return null;
  }

  /// Wait for Created event's matchId emitted by a transaction
  Future<BigInt?> waitForMatchIdFromTx(String txHash,
      {Duration timeout = const Duration(minutes: 5),
      Duration pollInterval = const Duration(seconds: 3)}) async {
    // Event signature for Created(uint256,address,address,uint256)
    final eventSig = bytesToHex(
      keccakUtf8('Created(uint256,address,address,uint256)'),
      include0x: true,
    );

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final receipt = await _client.getTransactionReceipt(txHash);
      if (receipt != null) {
        for (final log in receipt.logs) {
          try {
            final topics = log.topics;
            if (topics != null && topics.isNotEmpty) {
              final topic0 = topics[0].toString();
              if (topic0.toLowerCase() == eventSig.toLowerCase()) {
                if (topics.length > 1) {
                  final topic1 = topics[1].toString();
                  final hex =
                      topic1.startsWith('0x') ? topic1.substring(2) : topic1;
                  final matchId = BigInt.parse(hex, radix: 16);
                  return matchId;
                }
                // fallback: decode from non-indexed data
                final data = log.data ?? '';
                if (data.isNotEmpty) {
                  final hex = data.startsWith('0x') ? data.substring(2) : data;
                  if (hex.length >= 64) {
                    final first32 = hex.substring(0, 64);
                    final matchId = BigInt.parse(first32, radix: 16);
                    return matchId;
                  }
                }
              }
            }
          } catch (_) {}
        }
        return null;
      }
      await Future.delayed(pollInterval);
    }
    throw Exception('Timeout waiting for transaction receipt');
  }

  /// Get current gas price on Arc network
  Future<BigInt> getGasPrice() async {
    try {
      final gasPrice = await _client.getGasPrice();
      return gasPrice.getInWei;
    } catch (e) {
      throw Exception('Failed to get gas price: $e');
    }
  }

  void dispose() {
    _client.dispose();
  }

  // Contract ABIs
  static String _getEscrowAbi() {
    return '''[
  {
    "inputs": [
      {"internalType": "address", "name": "_operator", "type": "address"},
      {"internalType": "address", "name": "_treasury", "type": "address"},
      {"internalType": "uint256", "name": "_feeBps", "type": "uint256"}
    ],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "matchId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "player1", "type": "address"},
      {"indexed": true, "internalType": "address", "name": "player2", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256"}
    ],
    "name": "Created",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "matchId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "depositor", "type": "address"}
    ],
    "name": "Deposited",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "matchId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "winner", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "payout", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "fee", "type": "uint256"}
    ],
    "name": "Resolved",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "matchId", "type": "uint256"}
    ],
    "name": "Refunded",
    "type": "event"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "_operator", "type": "address"}
    ],
    "name": "setOperator",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "_feeBps", "type": "uint256"}
    ],
    "name": "setFeeBps",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "_treasury", "type": "address"}
    ],
    "name": "setTreasury",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "player2",  "type": "address"},
      {"internalType": "address", "name": "token", "type": "address"},
      {"internalType": "uint256", "name": "amount", "type": "uint256"},
      {"internalType": "uint256", "name": "expiresAt", "type": "uint256"}
    ],
    "name": "createMatch",
    "outputs": [
      {"internalType": "uint256", "name": "", "type": "uint256"}
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "matchId", "type": "uint256"}
    ],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "matchId", "type": "uint256"},
      {"internalType": "address", "name": "winner", "type": "address"}
    ],
    "name": "resolveMatch",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "matchId", "type": "uint256"}
    ],
    "name": "refundMatch",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "token", "type": "address"},
      {"internalType": "uint256", "name": "amount", "type": "uint256"},
      {"internalType": "address", "name": "to", "type": "address"}
    ],
    "name": "emergencyWithdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "matchId", "type": "uint256"}
    ],
    "name": "getMatch",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "player1", "type": "address"},
          {"internalType": "address", "name": "player2", "type": "address"},
          {"internalType": "address", "name": "token", "type": "address"},
          {"internalType": "uint256", "name": "amount", "type": "uint256"},
          {"internalType": "bool", "name": "p1Deposited", "type": "bool"},
          {"internalType": "bool", "name": "p2Deposited", "type": "bool"},
          {"internalType": "uint8", "name": "status", "type": "uint8"},
          {"internalType": "uint256", "name": "createdAt", "type": "uint256"},
          {"internalType": "uint256", "name": "expiresAt", "type": "uint256"},
          {"internalType": "uint256", "name": "depositedTotal", "type": "uint256"}
        ],
        "internalType": "struct TicTacToeEscrow.Match",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "matchId", "type": "uint256"}
    ],
    "name": "isMatchFunded",
    "outputs": [
      {"internalType": "bool", "name": "", "type": "bool"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
]''';
  }

  static String _getErc20Abi() {
    return '''[
  {
    "constant": false,
    "inputs": [
      {"name": "_spender", "type": "address"},
      {"name": "_value", "type": "uint256"}
    ],
    "name": "approve",
    "outputs": [{"name": "", "type": "bool"}],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [
      {"name": "_owner", "type": "address"},
      {"name": "_spender", "type": "address"}
    ],
    "name": "allowance",
    "outputs": [{"name": "", "type": "uint256"}],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [{"name": "_owner", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"name": "balance", "type": "uint256"}],
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {"name": "_to", "type": "address"},
      {"name": "_value", "type": "uint256"}
    ],
    "name": "transfer",
    "outputs": [{"name": "", "type": "bool"}],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [],
    "name": "decimals",
    "outputs": [{"name": "", "type": "uint8"}],
    "type": "function"
  }
]''';
  }
}
