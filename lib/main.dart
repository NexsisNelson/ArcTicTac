import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'wallet_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TicTacToe Arc (Testnet)',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TicTacToePage(),
    );
  }
}

class TicTacToePage extends StatefulWidget {
  const TicTacToePage({super.key});

  @override
  State<TicTacToePage> createState() => _TicTacToePageState();
}

const arcRpcUrl = 'https://YOUR_ARC_TESTNET_RPC_URL';
const usdcTokenAddress = '0x0000000000000000000000000000000000000000';
const escrowContractAddress = '0x0000000000000000000000000000000000000000';

class _TicTacToePageState extends State<TicTacToePage> {
  List<String> board = List.filled(9, '');
  String current = 'X';
  String status = 'X to move';
  bool gameOver = false;
  late final WalletService _walletService;
  bool _walletConnected = false;
  String _walletDisplay = 'Not connected';
  BigInt _nativeBalance = BigInt.zero;
  BigInt _usdcBalance = BigInt.zero;
  BigInt _usdcAllowance = BigInt.zero;
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  // Firebase / online fields
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _matchSub;
  DatabaseReference? _matchRef;
  String? _uid;
  String? _matchId;
  String? _symbol; // 'X' or 'O' for this player
  bool _onlineMode = false;
  bool _eloUpdated = false;

  // Match state
  String? _opponent;
  int _opponentRating = 1200;
  DateTime? _matchStartTime;
  DateTime? _waitTimeoutTime;
  Timer? _waitTimer;
  int _secondsUntilTimeout = 30;
  bool _isWaiting = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Offline';
  int _lastMoveTimestamp = 0;

  void reset() {
    setState(() {
      board = List.filled(9, '');
      current = 'X';
      status = 'X to move';
      gameOver = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _walletService = WalletService(
      rpcUrl: arcRpcUrl,
      usdcAddress: usdcTokenAddress,
    );
    _walletService.init();
    _ensureSignedIn();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      final cred = await _auth.signInAnonymously();
      _uid = cred.user?.uid;
    } else {
      _uid = _auth.currentUser?.uid;
    }
    // Ensure user record exists with default rating
    if (_uid != null) {
      final userRef = _db.child('users/$_uid');
      final snap = await userRef.get();
      if (!snap.exists) {
        await userRef.set({
          'rating': 1200,
          'lastSeen': ServerValue.timestamp,
        });
      } else {
        await userRef.update({'lastSeen': ServerValue.timestamp});
      }
    }
  }

  Future<void> _connectWallet() async {
    try {
      await _walletService.connect();
      setState(() {
        _walletConnected = _walletService.connected;
        _walletDisplay = _walletService.account?.hex ?? 'Connected';
      });
      await _refreshWalletBalances();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Wallet connect failed: $e')));
    }
  }

  Future<void> _disconnectWallet() async {
    await _walletService.disconnect();
    setState(() {
      _walletConnected = false;
      _walletDisplay = 'Not connected';
      _nativeBalance = BigInt.zero;
      _usdcBalance = BigInt.zero;
      _usdcAllowance = BigInt.zero;
    });
  }

  Future<void> _refreshWalletBalances() async {
    if (!_walletService.connected) return;
    final native = await _walletService.getNativeBalance();
    final usdc = await _walletService.getTokenBalance();
    final allowance =
        await _walletService.getTokenAllowance(escrowContractAddress);
    setState(() {
      _nativeBalance = native;
      _usdcBalance = usdc;
      _usdcAllowance = allowance;
    });
  }

  Future<void> _approveUsdc() async {
    try {
      final txHash = await _walletService.approveToken(
          escrowContractAddress, BigInt.from(10).pow(6) * BigInt.from(100));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Approve TX: $txHash')));
      await _refreshWalletBalances();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  Future<void> _transferUsdc() async {
    try {
      final recipient = _recipientController.text.trim();
      final amountText = _amountController.text.trim();
      if (recipient.isEmpty || amountText.isEmpty) {
        throw 'Recipient and amount required';
      }
      final amount = BigInt.from((double.parse(amountText) * 1e6).round());
      final txHash = await _walletService.transferToken(recipient, amount);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Transfer TX: $txHash')));
      await _refreshWalletBalances();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
    }
  }

  String _formatToken(BigInt amount, int decimals) {
    final divisor = BigInt.from(10).pow(decimals);
    final whole = amount ~/ divisor;
    final fraction = amount % divisor;
    final fractionStr = fraction.toString().padLeft(decimals, '0');
    return '$whole.${fractionStr.substring(0, min(6, decimals))}';
  }

  Future<int> _getMyRating() async {
    if (_uid == null) return 1200;
    final snap = await _db.child('users/$_uid/rating').get();
    if (!snap.exists) return 1200;
    final val = snap.value;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 1200;
    return 1200;
  }

  void playAt(int i) {
    if (gameOver) return;
    if (board[i] != '') return;
    if (_onlineMode) {
      // Only allow moves when it's this player's turn
      if (_symbol == null || current != _symbol) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not your turn')),
        );
        return;
      }

      // Rate limit moves (prevent spam)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastMoveTimestamp < 500) {
        return;
      }
      _lastMoveTimestamp = now;

      // Validate move locally
      final updated = List<String>.from(board);
      updated[i] = _symbol!;

      // Ensure no more than one move per turn
      final xCount = updated.where((e) => e == 'X').length;
      final oCount = updated.where((e) => e == 'O').length;
      if (xCount < oCount || xCount > oCount + 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid move sequence')),
        );
        return;
      }

      final winner = _computeWinnerFromList(updated);
      final next = _symbol == 'X' ? 'O' : 'X';
      final updates = {
        'board': updated,
        'current': winner == null ? next : '',
        'status': winner == null
            ? '$next to move'
            : (winner == 'Draw' ? 'Draw' : '$winner wins'),
        'lastMoveTime': ServerValue.timestamp,
      };
      _matchRef?.update(updates);
    } else {
      setState(() {
        board[i] = current;
        final winner = checkWinner();
        if (winner != null) {
          status = winner == 'Draw' ? 'Draw' : '$winner wins!';
          gameOver = true;
        } else {
          current = current == 'X' ? 'O' : 'X';
          status = '$current to move';
        }
      });
    }
  }

  String? _computeWinnerFromList(List<String> b) {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (var l in lines) {
      final a = b[l[0]];
      final c = b[l[2]];
      final bb = b[l[1]];
      if (a != '' && a == bb && bb == c) return a;
    }
    if (!b.contains('')) return 'Draw';
    return null;
  }

  String? checkWinner() {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (var l in lines) {
      final a = board[l[0]];
      final b = board[l[1]];
      final c = board[l[2]];
      if (a != '' && a == b && b == c) return a;
    }
    if (!board.contains('')) return 'Draw';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TicTacToe Arc (Testnet)'),
        actions: [
          IconButton(onPressed: reset, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(status, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_walletDisplay),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _walletConnected
                                ? _disconnectWallet
                                : _connectWallet,
                            child: Text(_walletConnected
                                ? 'Disconnect'
                                : 'Connect Wallet'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed:
                              _walletConnected ? _refreshWalletBalances : null,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Native balance: ${_formatToken(_nativeBalance, 18)}'),
                    Text('USDC balance: ${_formatToken(_usdcBalance, 6)}'),
                    Text('USDC allowance: ${_formatToken(_usdcAllowance, 6)}'),
                    TextField(
                      controller: _recipientController,
                      decoration: const InputDecoration(
                        labelText: 'Transfer to address',
                        hintText: '0x...',
                      ),
                    ),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'USDC amount',
                        hintText: '10.0',
                      ),
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _walletConnected ? _approveUsdc : null,
                            child: const Text('Approve Escrow'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _walletConnected ? _transferUsdc : null,
                            child: const Text('Transfer USDC'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_onlineMode) ...[
              Card(
                color: Colors.grey.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('You ($_symbol)',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              Text('Rating: ${_opponentRating}'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  _opponent != null
                                      ? 'vs ${_opponent!.substring(0, 8)}...'
                                      : 'vs Opponent',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              Text('Rating: $_opponentRating'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            label: Text(_connectionStatus),
                            backgroundColor: _connectionStatus == 'Connected'
                                ? Colors.green
                                : _connectionStatus == 'Waiting for opponent...'
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                          if (_isWaiting)
                            Chip(
                              label: Text('$_secondsUntilTimeout s'),
                              backgroundColor: Colors.orange.shade700,
                            ),
                          if (_matchStartTime != null)
                            Chip(
                              label: Text(
                                  'Match: ${DateTime.now().difference(_matchStartTime!).inMinutes}m'),
                              backgroundColor: Colors.blue,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: 9,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => playAt(i),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: board[i].isEmpty
                          ? Colors.blue.shade50
                          : (board[i] == 'X'
                              ? Colors.blue.shade100
                              : Colors.orange.shade100),
                    ),
                    child: Center(
                      child: Text(
                        board[i],
                        style: TextStyle(
                          fontSize: 48,
                          color: board[i] == 'X'
                              ? Colors.blue
                              : (board[i] == 'O' ? Colors.orange : null),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(onPressed: reset, child: const Text('Reset')),
                ElevatedButton(
                    onPressed: () {
                      // Placeholder: betting and Arc integration will be added later.
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Blockchain betting integration: upcoming')));
                    },
                    child: const Text('Place Bet (Testnet)')),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            if (!_onlineMode) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                        onPressed: _isConnecting ? null : _startMatchmaking,
                        child: Text(_isConnecting
                            ? 'Connecting...'
                            : 'Find Match (Firebase)')),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: gameOver ? _startMatchmaking : null,
                      child: const Text('Play Again'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _leaveMatch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Leave Game'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startMatchmaking() async {
    await _ensureSignedIn();
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });

    try {
      // Hardened matchmaking: transactionally join waiting matches using ELO and timeouts
      final myRating = await _getMyRating();
      final now = DateTime.now().millisecondsSinceEpoch;
      final waitingSnap = await _db
          .child('matches')
          .orderByChild('status')
          .equalTo('waiting')
          .get();
      bool joined = false;
      if (waitingSnap.exists) {
        for (final child in waitingSnap.children) {
          final key = child.key;
          if (key == null) continue;
          final data = child.value as Map<dynamic, dynamic>?;
          if (data == null) continue;
          // check expiry
          final expires = (data['expiresAt'] as int?) ?? 0;
          if (expires < now) {
            // stale - try to remove it (creator may have left)
            try {
              await _db.child('matches/$key').remove();
            } catch (_) {}
            continue;
          }
          final p1Rating = (data['player1_rating'] is int)
              ? data['player1_rating'] as int
              : (data['player1_rating'] is double)
                  ? (data['player1_rating'] as double).toInt()
                  : 1200;
          // ELO window (±200)
          if ((p1Rating - myRating).abs() > 200) continue;

          final ref = _db.child('matches/$key');
          // transactional join
          try {
            final result = await ref.runTransaction((mutableData) {
              final md = mutableData as dynamic;
              if (md == null) return Transaction.abort();
              final cur = md.value as Map<dynamic, dynamic>?;
              if (cur == null) return Transaction.abort();
              if (cur['player2'] != null) return Transaction.abort();
              final ex = (cur['expiresAt'] as int?) ?? 0;
              if (ex < DateTime.now().millisecondsSinceEpoch)
                return Transaction.abort();
              cur['player2'] = _uid;
              cur['player2_rating'] = myRating;
              cur['status'] = 'playing';
              cur['matchStartTime'] = ServerValue.timestamp;
              md.value = cur;
              return Transaction.success(md);
            });
            if (result.committed == true) {
              // joined successfully
              _matchRef = ref;
              _matchId = key;
              _symbol = 'O';
              _opponent = data['player1'] as String?;
              _opponentRating = p1Rating;
              _onlineMode = true;
              _isConnecting = false;
              _connectionStatus = 'Connected';
              _listenMatch();
              _startWaitTimeout();
              joined = true;
              break;
            }
          } catch (e) {
            // transaction failed or aborted, try next candidate
            continue;
          }
        }
      }
      if (!joined) {
        // create new match with expiry (timeout)
        final ref = _db.child('matches').push();
        final ttl = 30 * 1000; // 30 seconds
        final matchData = {
          'player1': _uid,
          'player1_rating': myRating,
          'player2': null,
          'board': List.filled(9, ''),
          'current': 'X',
          'status': 'waiting',
          'createdAt': now,
          'expiresAt': now + ttl,
        };
        await ref.set(matchData);
        _matchRef = ref;
        _matchId = ref.key;
        _symbol = 'X';
        _onlineMode = true;
        _isWaiting = true;
        _isConnecting = false;
        _connectionStatus = 'Waiting for opponent...';
        _waitTimeoutTime = DateTime.now().add(const Duration(seconds: 30));
        _startWaitCountdown();
        _listenMatch();
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Connection failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Matchmaking error: $e')),
      );
    }
    setState(() {});
  }

  void _startWaitCountdown() {
    _waitTimer?.cancel();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining =
          _waitTimeoutTime?.difference(DateTime.now()).inSeconds ?? 0;
      if (remaining <= 0) {
        timer.cancel();
        _leaveMatch();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Match timeout - no opponent found')),
        );
      } else {
        setState(() => _secondsUntilTimeout = remaining);
      }
    });
  }

  void _startWaitTimeout() {
    _waitTimer?.cancel();
  }

  void _listenMatch() {
    if (_matchRef == null) return;
    _matchSub = _matchRef!.onValue.listen((event) {
      final val = event.snapshot.value as Map<dynamic, dynamic>?;
      if (val == null) return;
      final b =
          (val['board'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              List.filled(9, '');
      final cur = val['current'] as String? ?? '';
      final stat = val['status'] as String? ?? '';

      // Extract opponent info if not set
      if (_symbol == 'O' && _opponent == null) {
        _opponent = val['player1'] as String?;
      } else if (_symbol == 'X' && _opponent == null) {
        _opponent = val['player2'] as String?;
      }

      // Extract match start time
      if (_matchStartTime == null && val['matchStartTime'] != null) {
        final timestamp = val['matchStartTime'] as int?;
        if (timestamp != null) {
          _matchStartTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }

      setState(() {
        board = b;
        current = cur == '' ? current : cur;
        status = stat == '' ? status : stat;
        gameOver = stat.contains('wins') || stat == 'Draw';

        if (stat == 'waiting') {
          _connectionStatus = 'Waiting for opponent...';
        } else if (stat == 'playing') {
          _isWaiting = false;
          _connectionStatus = 'In game';
        } else if (stat.contains('wins') || stat == 'Draw') {
          _connectionStatus = 'Match finished';
        }
      });
      // If match finished and we haven't applied ELO, do it once
      if (gameOver &&
          !_eloUpdated &&
          (stat == 'Draw' || stat.contains('wins'))) {
        _handleMatchEnd(val);
      }
    });
  }

  Future<int> _getRatingFor(String uid) async {
    final snap = await _db.child('users/$uid/rating').get();
    if (!snap.exists) return 1200;
    final val = snap.value;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 1200;
    return 1200;
  }

  int _calcEloNew(int ratingA, int ratingB, double scoreA, {int k = 32}) {
    final expectedA = 1 / (1 + pow(10, (ratingB - ratingA) / 400));
    final newA = ratingA + (k * (scoreA - expectedA)).round();
    return newA;
  }

  void _handleMatchEnd(Map<dynamic, dynamic> val) async {
    if (_eloUpdated) return;
    final p1 = val['player1'] as String?;
    final p2 = val['player2'] as String?;
    final statusVal = val['status'] as String? ?? '';
    if (p1 == null || p2 == null)
      return; // can't update ELO without two players

    double s1 = 0.5, s2 = 0.5;
    if (statusVal == 'Draw') {
      s1 = 0.5;
      s2 = 0.5;
    } else if (statusVal.contains('wins')) {
      if (statusVal.startsWith('X')) {
        s1 = 1.0;
        s2 = 0.0;
      } else if (statusVal.startsWith('O')) {
        s1 = 0.0;
        s2 = 1.0;
      }
    } else {
      // Unknown status formatting — default to draw
      s1 = 0.5;
      s2 = 0.5;
    }

    final r1 = await _getRatingFor(p1);
    final r2 = await _getRatingFor(p2);

    final new1 = _calcEloNew(r1, r2, s1);
    final new2 = _calcEloNew(r2, r1, s2);

    final updates = <String, dynamic>{
      'users/$p1/rating': new1,
      'users/$p2/rating': new2,
      if (_matchId != null) 'matches/$_matchId/result': statusVal,
      if (_matchId != null) 'matches/$_matchId/finalRatings/$p1': new1,
      if (_matchId != null) 'matches/$_matchId/finalRatings/$p2': new2,
    };

    try {
      await _db.update(updates);
      _eloUpdated = true;
    } catch (e) {
      // best-effort: set individually if multi-update fails
      if (_matchId != null) {
        await _db.child('users/$p1/rating').set(new1);
        await _db.child('users/$p2/rating').set(new2);
        await _db.child('matches/$_matchId/result').set(statusVal);
        await _db.child('matches/$_matchId/finalRatings/$p1').set(new1);
        await _db.child('matches/$_matchId/finalRatings/$p2').set(new2);
      }
      _eloUpdated = true;
    }
  }

  Future<void> _leaveMatch() async {
    _matchSub?.cancel();
    _waitTimer?.cancel();
    try {
      if (_matchRef != null && _symbol == 'X') {
        // if creator leaves, remove the match
        await _matchRef!.remove();
      } else if (_matchRef != null) {
        // if joining player leaves, clear player2
        await _matchRef!.update({'player2': null, 'status': 'waiting'});
      }
    } catch (e) {
      // Gracefully handle removal failures
    }
    _matchRef = null;
    _matchId = null;
    _symbol = null;
    _opponent = null;
    _onlineMode = false;
    _isWaiting = false;
    _matchStartTime = null;
    _connectionStatus = 'Offline';
    setState(() {});
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _waitTimer?.cancel();
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
