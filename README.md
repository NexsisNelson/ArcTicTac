# TicTacToe Arc (Testnet)

Minimal Flutter TicTacToe app intended as the starting point for Arc blockchain integration.

Quick start

1. Install Flutter SDK: https://flutter.dev/docs/get-started/install
2. Fetch dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

Next steps
- Implement matchmaking and real-time multiplayer.
- Add Arc smart contract escrow for USDC bets (testnet first).
- Integrate wallet auth and USDC token transfers.

Firebase setup (required for online multiplayer)

1. Create a Firebase project at https://console.firebase.google.com/
2. Add an Android and/or iOS app to the project and follow the platform setup steps.
	 - Download `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) and place them in the platform project directories.
3. Enable **Authentication → Sign-in method → Anonymous**.
4. Enable **Realtime Database** and set rules appropriate for development (restrict later):

Example quick rules for dev (replace before production):

```json
{
	"rules": {
		".read": true,
		".write": true
	}
}
```

5. Run `flutter pub get`, then launch the app.

Notes
- Platform-specific Firebase configuration is required before Firebase features will work.
- This scaffold includes a simple matchmaking prototype using Realtime Database under `matches/` nodes.
- Next: add bet escrow contract and USDC flows on Arc testnet.

Server-side validation (Cloud Functions)

I've added a Firebase Cloud Function prototype under `functions/` that listens for completed matches and validates the final board, computes winner, and updates ELO ratings atomically.

To deploy:

1. Install the Firebase CLI and login: https://firebase.google.com/docs/cli

```bash
cd functions
npm install
```

2. Initialize functions in your Firebase project if you haven't, then deploy:

```bash
firebase deploy --only functions:onBoardChange
```

Notes:
- The function performs basic legality checks (counts and single-winner). For robust anti-cheat, consider storing move history and additional server-side verification.
- Ensure `functions` uses Node 18 (see `functions/package.json`).

