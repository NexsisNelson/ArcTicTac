import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';

class WalletService {
  final String rpcUrl;
  final String usdcAddress;
  final String? escrowAddress;
  final WalletConnect connector;
  Web3Client? client;
  SessionStatus? session;

  WalletService({
    required this.rpcUrl,
    required this.usdcAddress,
    this.escrowAddress,
  }) : connector = WalletConnect(
          bridge: 'https://bridge.walletconnect.org',
          clientMeta: const PeerMeta(
            name: 'TicTacToe Arc',
            description: 'Arc testnet TicTacToe with USDC betting',
            url: 'https://example.com',
            icons: ['https://example.com/favicon.png'],
          ),
        );

  Future<void> init() async {
    client = Web3Client(rpcUrl, Client());
  }

  bool get connected => session != null && connector.connected;

  EthereumAddress? get account {
    if (session == null || session!.accounts.isEmpty) return null;
    return EthereumAddress.fromHex(session!.accounts.first);
  }

  Future<void> connect() async {
    if (connector.connected) {
      return;
    }
    session = await connector.createSession(onDisplayUri: (uri) async {
      final uriObj = Uri.parse(uri);
      if (await canLaunchUrl(uriObj)) {
        await launchUrl(uriObj, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $uri';
      }
    });
  }

  Future<void> disconnect() async {
    await connector.killSession();
    session = null;
  }

  Future<BigInt> getNativeBalance() async {
    final addr = account;
    if (addr == null || client == null) return BigInt.zero;
    final balance = await client!.getBalance(addr);
    return balance.getInWei;
  }

  Future<BigInt> getTokenBalance() async {
    final addr = account;
    if (addr == null || client == null) return BigInt.zero;
    final contract = _erc20Contract();
    final balanceFn = contract.function('balanceOf');
    final result = await client!.call(
      contract: contract,
      function: balanceFn,
      params: [addr],
    );
    return result.first as BigInt;
  }

  Future<BigInt> getTokenAllowance(String spender) async {
    final addr = account;
    if (addr == null || client == null) return BigInt.zero;
    final contract = _erc20Contract();
    final allowanceFn = contract.function('allowance');
    final result = await client!.call(
      contract: contract,
      function: allowanceFn,
      params: [addr, EthereumAddress.fromHex(spender)],
    );
    return result.first as BigInt;
  }

  Future<String> approveToken(String spender, BigInt amount) async {
    final addr = account;
    if (addr == null) throw Exception('Wallet not connected');
    final contract = _erc20Contract();
    final approveFn = contract.function('approve');
    final data =
        approveFn.encodeCall([EthereumAddress.fromHex(spender), amount]);
    return await _sendTx(to: EthereumAddress.fromHex(usdcAddress), data: data);
  }

  Future<String?> approveTokenIfNeeded(String spender, BigInt amount) async {
    final currentAllowance = await getTokenAllowance(spender);
    if (currentAllowance >= amount) {
      return null;
    }

    return await approveToken(spender, amount);
  }

  Future<int> getTokenDecimals() async {
    final contract = _erc20Contract();
    final decimalsFn = contract.function('decimals');
    final result = await client!.call(
      contract: contract,
      function: decimalsFn,
      params: [],
    );
    return (result.first as int);
  }

  Future<BigInt> getUsdcBalance() async {
    return getTokenBalance();
  }

  Future<BigInt> getUsdcAllowance(String spender) async {
    return getTokenAllowance(spender);
  }

  Future<String> transferToken(String recipient, BigInt amount) async {
    final addr = account;
    if (addr == null) throw Exception('Wallet not connected');
    final contract = _erc20Contract();
    final transferFn = contract.function('transfer');
    final data =
        transferFn.encodeCall([EthereumAddress.fromHex(recipient), amount]);
    return await _sendTx(to: EthereumAddress.fromHex(usdcAddress), data: data);
  }

  DeployedContract _erc20Contract() {
    final abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
    return DeployedContract(abi, EthereumAddress.fromHex(usdcAddress));
  }

  DeployedContract _escrowContract() {
    if (escrowAddress == null) throw Exception('Escrow address not configured');
    final abi = ContractAbi.fromJson(_escrowAbi, 'TicTacToeEscrow');
    return DeployedContract(abi, EthereumAddress.fromHex(escrowAddress!));
  }

  Future<String> _sendTx(
      {required EthereumAddress to, required Uint8List data}) async {
    final from = account;
    if (from == null) throw Exception('Wallet not connected');
    final tx = {
      'from': from.hex,
      'to': to.hex,
      'data': bytesToHex(data, include0x: true),
      'value': '0x0',
    };

    final result = await connector.sendCustomRequest(
      method: 'eth_sendTransaction',
      params: [tx],
    );
    return result.toString();
  }

  /// Waits for a transaction receipt and decodes the `Created` event to return the `matchId`.
  /// Use this after a WalletConnect createMatch tx to extract the on-chain match id.
  Future<BigInt?> waitForMatchIdFromTx(String txHash,
      {Duration timeout = const Duration(minutes: 5),
      Duration pollInterval = const Duration(seconds: 3)}) async {
    if (client == null) throw Exception('Web3 client not initialized');

    final contract = _escrowContract();
    final event = contract.event('MatchCreated');
    final eventSig = bytesToHex(event.signature, include0x: true);

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final receipt = await client!.getTransactionReceipt(txHash);
      if (receipt != null) {
        for (final log in receipt.logs) {
          final matchId = _tryDecodeMatchCreatedLog(event, eventSig, log);
          if (matchId != null) {
            return matchId;
          }
        }
        return null;
      }
      await Future.delayed(pollInterval);
    }
    throw Exception('Timeout waiting for transaction receipt');
  }

  BigInt? _tryDecodeMatchCreatedLog(
      ContractEvent event, String eventSig, FilterEvent log) {
    try {
      final topics = log.topics;
      if (topics == null || topics.isEmpty) return null;
      final topic0 = topics[0].toString();
      if (topic0.toLowerCase() != eventSig.toLowerCase()) return null;

      final data = log.data ?? '';
      final decoded = event.decodeResults(topics, data);
      if (decoded.isNotEmpty) {
        return decoded[0] as BigInt;
      }
    } catch (_) {
      // ignore malformed logs
    }
    return null;
  }

  /// Wait for a transaction receipt and return it (or null if not mined within timeout)
  Future<TransactionReceipt?> waitForTransactionReceipt(String txHash,
      {Duration timeout = const Duration(minutes: 5),
      Duration pollInterval = const Duration(seconds: 3)}) async {
    if (client == null) throw Exception('Web3 client not initialized');
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final receipt = await client!.getTransactionReceipt(txHash);
      if (receipt != null) return receipt;
      await Future.delayed(pollInterval);
    }
    return null;
  }
}

const String _erc20Abi = '''[
  {"constant":true,"inputs":[{"name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"},
  {"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"remaining","type":"uint256"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"spender","type":"address"},{"name":"value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"success","type":"bool"}],"type":"function"},
  {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"}
]''';

const String _escrowAbi = '''[
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"matchId","type":"uint256"},{"indexed":true,"internalType":"address","name":"player1","type":"address"},{"indexed":true,"internalType":"address","name":"player2","type":"address"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"expiresAt","type":"uint256"}],"name":"MatchCreated","type":"event"},
  {"inputs":[{"internalType":"address","name":"player2","type":"address"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"expiresAt","type":"uint256"}],"name":"createMatch","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"internalType":"uint256","name":"matchId","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"}
]''';
