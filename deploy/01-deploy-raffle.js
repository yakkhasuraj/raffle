const { network, ethers } = require('hardhat');
const { verify } = require('../utils/verify');
const {
    developmentChains,
    networkConfig,
} = require('../helper-hardhat-config');

const VRF_SUB_FUND_AMOUNT = ethers.utils.parseEther('30');
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

module.exports = async function ({ getNamedAccounts, deployments }) {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    let vrfCoordinatorV2Mock, vrfCoordinatorV2Address, subscriptionId;

    const { chainId } = network.config;

    if (developmentChains.includes(network.name)) {
        vrfCoordinatorV2Mock = await ethers.getContract('VRFCoordinatorV2Mock');
        vrfCoordinatorV2Address = vrfCoordinatorV2Mock.address;
        const transactionResponse =
            await vrfCoordinatorV2Mock.createSubscription();
        const transactionReceipt = await transactionResponse.wait(1);
        subscriptionId = transactionReceipt.events[0].args.subId;

        await vrfCoordinatorV2Mock.fundSubscription(
            subscriptionId,
            VRF_SUB_FUND_AMOUNT
        );
    } else {
        vrfCoordinatorV2Address = networkConfig[chainId].vrfCoordinatorV2;
        subscriptionId = networkConfig[chainId].subscriptionId;
    }

    const { entranceFee, keyHash, callbackGasLimit, interval } =
        networkConfig[chainId];

    const waitConfirmations = developmentChains.includes(network.name) ? 1 : 6;

    const args = [
        vrfCoordinatorV2Address,
        entranceFee,
        keyHash,
        subscriptionId,
        callbackGasLimit,
        interval,
    ];

    const raffle = await deploy('Raffle', {
        from: deployer,
        args,
        log: true,
        waitConfirmations,
    });

    if (developmentChains.includes(network.name)) {
        await vrfCoordinatorV2Mock.addConsumer(subscriptionId, raffle.address);
    }

    if (!developmentChains.includes(network.name) && ETHERSCAN_API_KEY) {
        await verify(raffle.address, args);
    }
};

module.exports.tags = ['all', 'raffle'];
