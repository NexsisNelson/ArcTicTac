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
  final WalletConnect connector;
  Web3Client? client;
  SessionStatus? session;

  WalletService({
    required this.rpcUrl,
    required this.usdcAddress,
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
}

const String _erc20Abi = '''[
  {"constant":true,"inputs":[{"name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"},
  {"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"remaining","type":"uint256"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"spender","type":"address"},{"name":"value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"success","type":"bool"}],"type":"function"}
]''';
