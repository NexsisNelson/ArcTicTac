import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
import 'wallet_service.dart';

const String _escrowAbi = '''[
  {"inputs":[{"internalType":"address","name":"player2","type":"address"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"expiresAt","type":"uint256"}],"name":"createMatch","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"internalType":"uint256","name":"matchId","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"}
]''';

/// Escrow helpers using WalletConnect (calls are signed by user's wallet)
extension WalletEscrowHelpers on WalletService {
  Future<Map<String, dynamic>> createMatchOnchain({
    required String player2Address,
    required String tokenAddress,
    required BigInt amount,
    required BigInt expiresAt,
  }) async {
    if (escrowAddress == null) throw Exception('Escrow address not configured');
    final abi = ContractAbi.fromJson(_escrowAbi, 'TicTacToeEscrow');
    final contract =
        DeployedContract(abi, EthereumAddress.fromHex(escrowAddress!));
    final fn = contract.function('createMatch');
    final data = fn.encodeCall([
      EthereumAddress.fromHex(player2Address),
      EthereumAddress.fromHex(tokenAddress),
      amount,
      expiresAt,
    ]);
    final txHash =
        await _sendTx(to: EthereumAddress.fromHex(escrowAddress!), data: data);
    // Poll receipt and attempt to decode matchId from Created event
    BigInt? matchId;
    try {
      matchId = await waitForMatchIdFromTx(txHash);
    } catch (_) {
      matchId = null;
    }

    return {'txHash': txHash, 'matchId': matchId};
  }

  Future<Map<String, dynamic>> depositOnchain({required BigInt matchId}) async {
    if (escrowAddress == null) throw Exception('Escrow address not configured');
    final abi = ContractAbi.fromJson(_escrowAbi, 'TicTacToeEscrow');
    final contract =
        DeployedContract(abi, EthereumAddress.fromHex(escrowAddress!));
    final fn = contract.function('deposit');
    final data = fn.encodeCall([matchId]);
    final txHash =
        await _sendTx(to: EthereumAddress.fromHex(escrowAddress!), data: data);

    // Wait for confirmation and return status
    final receipt = await waitForTransactionReceipt(txHash);
    final status = receipt?.status;
    return {'txHash': txHash, 'status': status};
  }
}
