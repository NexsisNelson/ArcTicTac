import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../wallet_service.dart';
import '../wallet_escrow_helpers.dart';
import '../escrow_service.dart';

class BetFlowPage extends StatefulWidget {
  final WalletService walletService;
  final EscrowService escrowService;

  const BetFlowPage({
    Key? key,
    required this.walletService,
    required this.escrowService,
  }) : super(key: key);

  @override
  State<BetFlowPage> createState() => _BetFlowPageState();
}

class _BetFlowPageState extends State<BetFlowPage> {
  final _amountController = TextEditingController(text: '1');
  final _opponentController = TextEditingController();
  final _matchIdController = TextEditingController();
  bool _loading = false;
  BigInt _usdcBalance = BigInt.zero;
  BigInt _usdcAllowance = BigInt.zero;
  int _usdcDecimals = 6;
  String? _walletAddress;

  @override
  void initState() {
    super.initState();
    _refreshBalances();
  }

  Future<void> _refreshBalances() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _walletAddress = widget.walletService.account?.hex;
      _usdcDecimals = await widget.walletService.getTokenDecimals();
      final addr = widget.walletService.account?.hex;
      if (addr != null) {
        _usdcBalance = await widget.walletService.getUsdcBalance();
        if (widget.walletService.escrowAddress != null) {
          _usdcAllowance = await widget.walletService
              .getUsdcAllowance(widget.walletService.escrowAddress!);
        }
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatUsdc(BigInt amount) {
    final divisor = BigInt.from(10).pow(_usdcDecimals);
    final whole = amount ~/ divisor;
    final fraction = (amount % divisor).toString().padLeft(_usdcDecimals, '0');
    final displayFraction = fraction.substring(0, min(6, fraction.length));
    return '$whole.$displayFraction';
  }

  BigInt _parseUsdc(String text) {
    // USDC typically uses 6 decimals
    final parts = text.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    int frac = 0;
    if (parts.length > 1) {
      final f = (parts[1] + '000000').substring(0, 6);
      frac = int.tryParse(f) ?? 0;
    }
    return BigInt.from(whole) * BigInt.from(1000000) + BigInt.from(frac);
  }

  Future<void> _approve() async {
    final escrowAddr = widget.walletService.escrowAddress;
    if (escrowAddr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escrow address not configured')));
      return;
    }
    final amount = _parseUsdc(_amountController.text);
    setState(() => _loading = true);
    try {
      final tx = await widget.walletService.approveToken(escrowAddr, amount);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Approve tx: $tx')));
      await Future.delayed(const Duration(seconds: 2));
      await _refreshBalances();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createMatch() async {
    final opponent = _opponentController.text.trim();
    if (opponent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter opponent address')));
      return;
    }
    final amount = _parseUsdc(_amountController.text);
    final expiresAt = BigInt.from(DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000);
    setState(() => _loading = true);
    try {
      final escrowAddr = widget.walletService.escrowAddress;
      if (escrowAddr == null) {
        throw 'Escrow address not configured';
      }
      final currentAllowance =
          await widget.walletService.getUsdcAllowance(escrowAddr);
      if (currentAllowance < amount) {
        final approvalTx =
            await widget.walletService.approveTokenIfNeeded(escrowAddr, amount);
        if (approvalTx != null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Approval tx: $approvalTx')));
          await Future.delayed(const Duration(seconds: 2));
          await _refreshBalances();
        }
      }

      final result = await widget.walletService.createMatchOnchain(
        player2Address: opponent,
        tokenAddress: widget.walletService.usdcAddress,
        amount: amount,
        expiresAt: expiresAt,
      );
      final txHash = result['txHash'] as String?;
      final matchId = result['matchId'] as BigInt?;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'createMatch tx: ${txHash ?? 'unknown'}; matchId: ${matchId?.toString() ?? 'pending'}')));
      if (matchId != null) {
        _matchIdController.text = matchId.toString();
        try {
          final db = FirebaseDatabase.instance.ref();
          final player1 = widget.walletService.account?.hex ?? 'unknown';
          await db.child('matches').child(matchId.toString()).set({
            'player1': player1,
            'player2': opponent,
            'token': widget.walletService.usdcAddress,
            'amount': amount.toString(),
            'status': 'waiting',
            'createdAt': ServerValue.timestamp,
            'expiresAt': expiresAt.toString(),
            'escrowTxHash': txHash,
          });
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Firebase match record created')));
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Firebase create failed: $e')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deposit() async {
    final matchIdText = _matchIdController.text.trim();
    if (matchIdText.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter matchId')));
      return;
    }
    final matchId = BigInt.parse(matchIdText);
    setState(() => _loading = true);
    try {
      final match = await widget.escrowService.getMatch(matchId: matchId);
      final amount = match['amount'] as BigInt;
      final escrowAddr = widget.walletService.escrowAddress;
      if (escrowAddr == null) {
        throw 'Escrow address not configured';
      }
      final currentAllowance =
          await widget.walletService.getUsdcAllowance(escrowAddr);
      if (currentAllowance < amount) {
        final approvalTx =
            await widget.walletService.approveTokenIfNeeded(escrowAddr, amount);
        if (approvalTx != null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Approval tx: $approvalTx')));
          await Future.delayed(const Duration(seconds: 2));
          await _refreshBalances();
        }
      }

      final result =
          await widget.walletService.depositOnchain(matchId: matchId);
      final txHash = result['txHash'] as String?;
      final status = result['status'] as bool?;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('deposit tx: ${txHash ?? 'unknown'}')));

      // If confirmed, update Firebase match deposit record
      if (status == true) {
        try {
          final db = FirebaseDatabase.instance.ref();
          final account = widget.walletService.account?.hex ?? 'unknown';
          await db
              .child('matches')
              .child(matchId.toString())
              .child('onchainDeposits')
              .child(account)
              .set({'txHash': txHash, 'confirmedAt': ServerValue.timestamp});
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deposit confirmed and recorded')));
        } catch (e) {
          // ignore firebase write errors but log
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update Firebase: $e')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deposit failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bet Flow')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: widget.walletService.connected
                      ? null
                      : () async {
                          await widget.walletService.connect();
                          await widget.walletService.init();
                          await widget.escrowService.init();
                          await _refreshBalances();
                          setState(() {});
                        },
                  child: Text(widget.walletService.connected
                      ? 'Connected'
                      : 'Connect Wallet'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: _refreshBalances, child: const Text('Refresh')),
              ],
            ),
            const SizedBox(height: 12),
            if (_walletAddress != null) Text('Wallet: ${_walletAddress!}'),
            const SizedBox(height: 8),
            Text('USDC Balance: ${_formatUsdc(_usdcBalance)}'),
            Text('USDC Allowance: ${_formatUsdc(_usdcAllowance)}'),
            const SizedBox(height: 12),
            TextField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Bet amount (USDC)')),
            TextField(
                controller: _opponentController,
                decoration: const InputDecoration(
                    labelText: 'Opponent address (optional)')),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(
                  onPressed: _approve, child: const Text('Approve USDC')),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _createMatch, child: const Text('Create Match')),
            ]),
            const Divider(height: 24),
            TextField(
                controller: _matchIdController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Match ID to deposit')),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _deposit, child: const Text('Deposit to Match')),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
