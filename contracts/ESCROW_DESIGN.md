
# Solidity Escrow Design (Arc / EVM-compatible)

The escrow implementation will use Solidity on Arc (EVM-compatible). The initial contract is implemented at `contracts/Escrow.sol` as a pragmatic operator-resolved escrow for USDC-like ERC20 tokens.

Key points
- Uses `createMatch`, `deposit`, `resolveMatch`, and `refundMatch` semantics.
- Operator (configured at deployment) calls `resolveMatch` after off-chain game validation (e.g., Cloud Function).
- Fees are supported via `feeBps` and paid to a treasury address.
- Protects against race conditions by tracking deposited flags and statuses; transfer operations use low-level checks to support tokens that do/don't return booleans.

Next steps
- Adapt and test `contracts/Escrow.sol` on Arc testnet with a test USDC token address.
- Implement client-side approve + deposit flow in Flutter.
- Secure operator private key for backend Cloud Function to call `resolveMatch`.

