require('@nomicfoundation/hardhat-chai-matchers');
require('@nomicfoundation/hardhat-toolbox');
require('hardhat-contract-sizer');
require('hardhat-deploy');
require('dotenv').config();

const GOERLI_RPC_URL = process.env.GOERLI_RPC_URL;
const GOERLI_PRIVATE_KEY = process.env.GOERLI_PRIVATE_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    defaultNetwork: 'hardhat',
    solidity: '0.8.17',
    networks: {
        goerli: {
            url: GOERLI_RPC_URL,
            accounts: [GOERLI_PRIVATE_KEY],
            chainId: 5,
        },
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY,
    },
    gasReporter: {
        enabled: true,
        outputFile: 'gas-report.txt',
        noColors: true,
    },
    namedAccounts: {
        deployer: { default: 0 },
        player: { default: 1 },
    },
    mocha: {
        timeout: 200000,
    },
};
