const String arcRpcUrl = String.fromEnvironment(
  'ARC_RPC_URL',
  defaultValue: 'https://rpc.testnet.arc.network',
);

const String usdcTokenAddress = String.fromEnvironment(
  'USDC_TOKEN_ADDRESS',
  defaultValue: '0x6615D7d7865bF00a8FED65d7FB24429078Aa82C4',
);

const String escrowContractAddress = String.fromEnvironment(
  'ESCROW_CONTRACT_ADDRESS',
  defaultValue: '0x25b088219f1B1e7F795Df299f1218A3999D7509d',
);
