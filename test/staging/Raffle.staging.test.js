const { assert, expect } = require('chai');
const { ethers, network, getNamedAccounts } = require('hardhat');
const { developmentChains } = require('../../helper-hardhat-config');

developmentChains.includes(network.name)
    ? describe.skip
    : describe('Raffle Staging Test', function () {
          let raffle, entranceFee, deployer;

          beforeEach(async function () {
              deployer = (await getNamedAccounts()).deployer;
              raffle = await ethers.getContract('Raffle', deployer);
              entranceFee = await raffle.getEntranceFee();
          });

          describe('fulfillRandomWords', function () {
              it('works with live Chainlink Keepers and VRF, we get a random winner', async function () {
                  const startingTimeStamp = await raffle.getLastTimeStamp();
                  const accounts = await ethers.getSigners();

                  await new Promise(async (resolve, reject) => {
                      raffle.once('WinnerPicked', async () => {
                          console.log('Event fired!');

                          try {
                              const recentWinner =
                                  await raffle.getRecentWinner();
                              const raffleState = await raffle.getRaffleState();
                              const winnerEndingBalance =
                                  await accounts[0].getBalance();
                              const endingTimeStamp =
                                  await raffle.getLastTimeStamp();

                              await expect(
                                  raffle.getPlayer(0)
                              ).to.be.reverted();
                              assert.equal(
                                  recentWinner.toString(),
                                  accounts[0].address
                              );
                              assert.equal(raffleState, 0);
                              assert.equal(
                                  winnerEndingBalance.toString(),
                                  winnerStartingBalance
                                      .add(entranceFee)
                                      .toString()
                              );
                              assert(endingTimeStamp > startingTimeStamp);
                              resolve();
                          } catch (error) {
                              console.log('error', error);
                              reject(error);
                          }
                      });

                      await raffle.enterRaffle({ value: entranceFee });
                      const winnerStartingBalance =
                          await accounts[0].getBalance();
                  });
              });
          });
      });
