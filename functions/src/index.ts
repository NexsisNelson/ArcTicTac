import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const K = 32;

function expectedScore(rA: number, rB: number) {
  return 1 / (1 + Math.pow(10, (rB - rA) / 400));
}

function calcNewRating(rA: number, rB: number, sA: number) {
  const exp = expectedScore(rA, rB);
  return Math.round(rA + K * (sA - exp));
}

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

export const onBoardChange = functions.database
  .ref('/matches/{matchId}/board')
  .onWrite(async (change, context) => {
    const matchId = context.params.matchId;
    const board = change.after.val();
    if (!board) return null;

    const matchSnap = await admin.database().ref(`/matches/${matchId}`).get();
    const match = matchSnap.val();
    if (!match) return null;
    if (match.result) return null; // already finished

    if (!Array.isArray(board) || board.length !== 9) {
      await admin.database().ref(`/matches/${matchId}/invalid`).set({
        reason: 'invalid_board_shape',
        ts: Date.now(),
      });
      return null;
    }

    // basic legality: counts of X and O
    const counts = { X: 0, O: 0 };
    for (const v of board) {
      if (v === 'X') counts.X++;
      if (v === 'O') counts.O++;
    }
    if (!(counts.X === counts.O || counts.X === counts.O + 1)) {
      await admin.database().ref(`/matches/${matchId}/invalid`).set({
        reason: 'invalid_counts',
        counts,
        ts: Date.now(),
      });
      return null;
    }

    // determine winner
    let winner: string | null = null;
    for (const l of lines) {
      const a = board[l[0]];
      const b = board[l[1]];
      const c = board[l[2]];
      if (a && a === b && b === c) {
        if (winner && winner !== a) {
          await admin.database().ref(`/matches/${matchId}/invalid`).set({
            reason: 'both_winners',
            ts: Date.now(),
          });
          return null;
        }
        winner = a;
      }
    }

    let result = '';
    if (winner) result = `${winner} wins`;
    else if (board.every((cell: any) => cell === 'X' || cell === 'O')) result = 'Draw';
    else return null; // not finished yet

    // Must have two players
    const p1 = match.player1;
    const p2 = match.player2;
    if (!p1 || !p2) return null;

    const r1snap = await admin.database().ref(`/users/${p1}/rating`).get();
    const r2snap = await admin.database().ref(`/users/${p2}/rating`).get();
    const r1 = r1snap.exists() ? Number(r1snap.val()) : 1200;
    const r2 = r2snap.exists() ? Number(r2snap.val()) : 1200;

    let s1 = 0.5,
      s2 = 0.5;
    if (result === 'Draw') {
      s1 = 0.5;
      s2 = 0.5;
    } else if (result.startsWith('X')) {
      s1 = 1;
      s2 = 0;
    } else {
      s1 = 0;
      s2 = 1;
    }

    const new1 = calcNewRating(r1, r2, s1);
    const new2 = calcNewRating(r2, r1, s2);

    const updates: any = {};
    updates[`/matches/${matchId}/result`] = result;
    updates[`/matches/${matchId}/finalRatings/${p1}`] = new1;
    updates[`/matches/${matchId}/finalRatings/${p2}`] = new2;
    updates[`/users/${p1}/rating`] = new1;
    updates[`/users/${p2}/rating`] = new2;

    await admin.database().ref().update(updates);
    return null;
  });
