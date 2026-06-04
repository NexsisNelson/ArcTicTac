require('@nomicfoundation/hardhat-toolbox');

const accounts = process.env.DEPLOYER_PRIVATE_KEY
  ? [process.env.DEPLOYER_PRIVATE_KEY]
  : [];

module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.19',
      },
    ],
  },
  networks: {
    arc: {
      url: process.env.ARC_RPC_URL || 'https://rpc.testnet.arc.network',
      chainId: process.env.ARC_CHAIN_ID ? Number(process.env.ARC_CHAIN_ID) : 5042002,
      accounts,
      gas: 'auto',
      gasPrice: 'auto',
    },
  },
  paths: {
    sources: './src',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
};
