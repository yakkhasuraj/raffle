const { assert, expect } = require('chai');
const { network, getNamedAccounts, ethers } = require('hardhat');
const {
    developmentChains,
    networkConfig,
} = require('../../helper-hardhat-config');

!developmentChains.includes(network.name)
    ? describe.skip
    : describe('Raffle Unit Test', function () {
          let raffle, vrfCoordinatorV2Mock, entranceFee, deployer, interval;
          const { chainId } = network.config;

          beforeEach(async function () {
              deployer = (await getNamedAccounts()).deployer;

              await deployments.fixture(['all']);
              raffle = await ethers.getContract('Raffle', deployer);
              vrfCoordinatorV2Mock = await ethers.getContract(
                  'VRFCoordinatorV2Mock',
                  deployer
              );
              entranceFee = await raffle.getEntranceFee();
              interval = await raffle.getInterval();
          });

          describe('constructor', function () {
              it('initializes the raffle', async function () {
                  const raffleState = await raffle.getRaffleState();
                  const interval = await raffle.getInterval();
                  assert.equal(raffleState.toString(), '0');
                  assert.equal(
                      interval.toString(),
                      networkConfig[chainId].interval
                  );
              });
          });

          describe('enterRaffle', function () {
              it("reverts when you don't pay enough", async function () {
                  await expect(
                      raffle.enterRaffle()
                  ).to.be.revertedWithCustomError(
                      raffle,
                      'Raffle_NotEnoughETHEntered'
                  );
              });

              it('return player when they enter', async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  const player = await raffle.getPlayer(0);
                  assert.equal(player, deployer);
              });

              it('emits event on enter', async function () {
                  await expect(
                      raffle.enterRaffle({ value: entranceFee })
                  ).to.emit(raffle, 'RaffleEnter');
              });

              it("doesn't allow entrance when raffle is calculating", async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);

                  await raffle.performUpkeep([]);
                  await expect(
                      raffle.enterRaffle({ value: entranceFee })
                  ).to.be.revertedWithCustomError(raffle, 'Raffle_NotOpen');
              });
          });

          describe('checkUpkeep', function () {
              it("returns false if people haven't sent any ETH", async function () {
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);

                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep(
                      []
                  );
                  assert(!upkeepNeeded);
              });

              it("returns false if raffle isn't open", async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);
                  await raffle.performUpkeep([]);

                  const raffleState = await raffle.getRaffleState();
                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep(
                      []
                  );
                  assert.equal(raffleState.toString(), '1');
                  assert.equal(upkeepNeeded, false);
              });

              it("returns false if enough time hasn't passed", async () => {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() - 5,
                  ]);
                  await network.provider.request({
                      method: 'evm_mine',
                      params: [],
                  });

                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep(
                      '0x'
                  );
                  assert(!upkeepNeeded);
              });

              it('returns true if enough time has passed, has player, eth, and is open', async () => {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.request({
                      method: 'evm_mine',
                      params: [],
                  });

                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep(
                      '0x'
                  );
                  assert(upkeepNeeded);
              });
          });

          describe('performUpkeep', function () {
              it('can only run when checkUpkeep is true', async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);

                  const transaction = await raffle.performUpkeep([]);
                  assert(transaction);
              });

              it('reverts when checkUpkeep is false', async function () {
                  await expect(raffle.performUpkeep([])).to.be.rejectedWith(
                      'Raffle_UpkeepNotNeeded'
                  );
              });

              it('updates the raffleState, emits an event, and calls the vrfCoordinator', async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);

                  const transactionResponse = await raffle.performUpkeep([]);
                  const transactionReceipt = await transactionResponse.wait(1);
                  const { requestId } = transactionReceipt.events[1].args;
                  const raffleState = await raffle.getRaffleState();

                  assert(requestId.toNumber() > 0);
                  assert(raffleState == 1);
              });
          });

          describe('fulfillRandomWords', function () {
              beforeEach(async function () {
                  await raffle.enterRaffle({ value: entranceFee });
                  await network.provider.send('evm_increaseTime', [
                      interval.toNumber() + 1,
                  ]);
                  await network.provider.send('evm_mine', []);
              });

              it('can only be called after performUpkeep', async function () {
                  await expect(
                      vrfCoordinatorV2Mock.fulfillRandomWords(0, raffle.address)
                  ).to.be.revertedWith('nonexistent request');
                  await expect(
                      vrfCoordinatorV2Mock.fulfillRandomWords(1, raffle.address)
                  ).to.be.revertedWith('nonexistent request');
              });

              it('picks a winner, resets, and sends money', async function () {
                  const additionalEntrants = 3;
                  const startingAccountIndex = 1;
                  const accounts = await ethers.getSigners();
                  for (
                      let i = startingAccountIndex;
                      i < startingAccountIndex + additionalEntrants;
                      i++
                  ) {
                      const accountConnectRaffle = raffle.connect(accounts[i]);
                      await accountConnectRaffle.enterRaffle({
                          value: entranceFee,
                      });
                  }
                  const startingTimeStamp = await raffle.getLastTimeStamp();

                  await new Promise(async (resolve, reject) => {
                      raffle.once('WinnerPicked', async () => {
                          try {
                              console.log('Event found!');

                              const recentWinner =
                                  await raffle.getRecentWinner();
                              const raffleState = await raffle.getRaffleState();
                              const endingTimeStamp =
                                  await raffle.getLastTimeStamp();
                              const numberOfPlayers =
                                  await raffle.getNumberOfPlayers();
                              const winnerEndingBalance =
                                  await accounts[1].getBalance();

                              assert.equal(numberOfPlayers.toString(), '0');
                              assert.equal(raffleState.toString(), '0');
                              assert(endingTimeStamp > startingTimeStamp);
                              assert.equal(
                                  winnerEndingBalance.toString(),
                                  winnerStartingBalance.add(
                                      entranceFee
                                          .mul(additionalEntrants)
                                          .add(entranceFee)
                                          .toString()
                                  )
                              );
                              resolve();
                          } catch (error) {
                              reject(error);
                          }
                      });

                      const transaction = await raffle.performUpkeep([]);
                      const transactionReceipt = await transaction.wait(1);
                      const winnerStartingBalance =
                          await accounts[1].getBalance();
                      await vrfCoordinatorV2Mock.fulfillRandomWords(
                          transactionReceipt.events[1].args.requestId,
                          raffle.address
                      );
                  });
              });
          });
      });
