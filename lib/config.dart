const String arcRpcUrl = String.fromEnvironment(
  'ARC_RPC_URL',
  defaultValue: 'https://YOUR_ARC_TESTNET_RPC_URL',
);

const String usdcTokenAddress = String.fromEnvironment(
  'USDC_TOKEN_ADDRESS',
  defaultValue: '0x0000000000000000000000000000000000000000',
);

const String escrowContractAddress = String.fromEnvironment(
  'ESCROW_CONTRACT_ADDRESS',
  defaultValue: '0xA1a7A4Aa5EF92ca0390dD46D38e527a3CE020Cf3',
);
