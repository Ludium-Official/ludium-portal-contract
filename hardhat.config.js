require('@nomicfoundation/hardhat-toolbox');
require('dotenv').config();

const { RPC_URL, PRIVATE_KEY, CHAIN_ID } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  defaultNetwork: 'hardhat',
  networks: {
    arbitrumSepolia: {
      url: RPC_URL,
      chainId: parseInt(CHAIN_ID),
      accounts: [PRIVATE_KEY],
    },
  },
  paths: {
    sources: './contracts',
    artifacts: './artifacts',
    cache: './cache',
    tests: './test',
  },
};
