# Smart Contract Audit & Security Checklist

This checklist is tailored to `contracts/Escrow.sol` and the surrounding Flutter / Firebase integration.

## 1. Core contract security

- [ ] Verify contract compiler version is pinned (`pragma solidity ^0.8.19`) and no unsafe compiler flags are enabled.
- [ ] Confirm constructor parameters are validated:
  - `operator != address(0)`
  - `feeBps <= 500`
- [ ] Check ownership and access control:
  - `onlyOwner` protects `setTreasury`, `setOperator`, `setFeeBps`, `emergencyWithdraw`
  - `onlyOperator` protects `resolveMatch`
- [ ] Confirm `nonReentrant` guard exists and is applied to state-changing functions that perform token transfers.
- [ ] Ensure event emissions are consistent and include useful indexed fields for off-chain tracking.

## 2. Funds and token handling

- [ ] Verify `createMatch` uses safe parameters and does not transfer funds directly.
- [ ] Confirm `deposit`:
  - only accepts player1 or player2
  - blocks duplicate deposits
  - enforces expiration (`block.timestamp <= expiresAt`)
  - updates state before emitting events
- [ ] Confirm `resolveMatch`:
  - only operator can call it
  - requires both players deposited
  - checks valid winner address
  - calculates fee as `total * feeBps / 10000`
  - updates status to `Resolved` before transfers (CEI)
- [ ] Confirm `refundMatch`:
  - only after expiry
  - refunds both p1 and p2 deposits if present
  - updates status to `Cancelled` before transfers
- [ ] Confirm `emergencyWithdraw` uses owner-only guard and rejects `address(0)`.
- [ ] Confirm token transfers are wrapped with `call` and require return conditions, supporting non-standard ERC20s.

## 3. Event and off-chain integration checks

- [ ] Verify match creation emits `MatchCreated` with expected fields.
- [ ] Verify deposit and match funding events are emitted for both players.
- [ ] Confirm the app’s receipt parser uses ABI decoding, not only raw topic order, to support event field changes.
- [ ] Confirm `matchId` extraction works for both indexed and non-indexed event fields.
- [ ] Validate off-chain flows:
  - `createMatchOnchain()` records the Firebase match record once `matchId` is decoded.
  - `depositOnchain()` waits for transaction confirmation before updating Firebase.

## 4. Access control & replay protections

- [ ] Confirm `joinMatch` does not allow unauthorized player assignment when `player2` is already set.
- [ ] Review any potential race between `createMatch` and `joinMatch` if `player2 == address(0)`.
- [ ] Ensure there is no missing check for `msg.sender` in critical flows.

## 5. Token-specific risks

- [ ] Confirm support for tokens that do not return a boolean on `transfer` / `transferFrom`.
- [ ] Check for fee-on-transfer or rebasing token risks; understand that `deposit` assumes fixed `amount` received.
- [ ] Validate that deposited token type is trusted or whitelisted if using non-standard tokens.

## 6. Time and expiration risks

- [ ] Validate how `expiresAt` is chosen from the frontend and whether a too-short expiration can break the UX.
- [ ] Confirm `refundMatch` can only be called after actual expiry.
- [ ] Consider if `createMatch` should require `expiresAt > block.timestamp + MIN_DURATION`.

## 7. Gas, performance, and fallback conditions

- [ ] Review gas costs for `deposit`, `resolveMatch`, and `refundMatch`.
- [ ] Ensure `resolveMatch` and `refundMatch` do not exceed block gas limits for expected token transfer flows.
- [ ] Ensure the contract does not lock funds if `transfer` succeeds but transfer callback fails.

## 8. Testing checklist

- [ ] Unit test `createMatch` positive and negative cases.
- [ ] Unit test `deposit` for:
  - player1 deposit
  - player2 deposit
  - duplicate deposit rejects
  - expired match rejects
  - non-participant rejects
- [ ] Unit test `resolveMatch` for:
  - operator success
  - non-operator revert
  - invalid winner revert
  - fee and payout amounts
- [ ] Unit test `refundMatch` for:
  - expiry-based refund
  - partial deposits refund
  - status update to `Cancelled`
- [ ] Unit test `setOperator`, `setTreasury`, `setFeeBps`, and `emergencyWithdraw` access control.
- [ ] Confirm `isMatchFunded` and `getMatch` readers return expected state.

## 9. Deployment and environment checks

- [ ] Confirm the deployed network uses the correct Arc testnet RPC and chain ID.
- [ ] Confirm operator private keys are stored securely and never embedded in client code.
- [ ] Confirm Firebase node rules protect match records and do not expose off-chain operator data.
- [ ] Confirm the UI only writes the Firebase match record after the on-chain `matchId` is reliably decoded.

## 10. Additional audit considerations

- [ ] Run static analysis with Slither, MythX, or another Solidity scanner.
- [ ] Run a test harness against a full local chain and fuzz edge cases.
- [ ] Confirm the contract uses the Checks-Effects-Interactions pattern consistently.
- [ ] Validate any on-chain/off-chain coupling, including Cloud Function truth assumptions.
- [ ] Evaluate whether an operator can cause unintended refunds or incorrectly resolve a match.
