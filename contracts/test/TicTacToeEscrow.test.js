const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('TicTacToeEscrow', function () {
  let owner;
  let operator;
  let treasury;
  let player1;
  let player2;
  let other;
  let operatorAddress;
  let treasuryAddress;
  let player1Address;
  let player2Address;
  let otherAddress;
  let token;
  let escrow;
  let tokenAddress;
  let escrowAddress;
  const feeBps = 200;

  beforeEach(async function () {
    [owner, operator, treasury, player1, player2, other] = await ethers.getSigners();
    operatorAddress = await operator.getAddress();
    treasuryAddress = await treasury.getAddress();
    player1Address = await player1.getAddress();
    player2Address = await player2.getAddress();
    otherAddress = await other.getAddress();

    const MockERC20 = await ethers.getContractFactory('MockERC20');
    token = await MockERC20.deploy(
      'Mock USDC',
      'mUSDC',
      6,
      ethers.parseUnits('1000000', 6)
    );

    tokenAddress = await token.getAddress();

    await token.transfer(player1Address, ethers.parseUnits('1000', 6));
    await token.transfer(player2Address, ethers.parseUnits('1000', 6));

    const Escrow = await ethers.getContractFactory('TicTacToeEscrow');
    escrow = await Escrow.deploy(operatorAddress, treasuryAddress, feeBps);
    escrowAddress = await escrow.getAddress();
  });

  it('deploys with correct operator and treasury', async function () {
    expect(await escrow.operator()).to.equal(operatorAddress);
    expect(await escrow.treasury()).to.equal(treasuryAddress);
    expect(await escrow.feeBps()).to.equal(feeBps);
  });

  it('creates a match and emits MatchCreated', async function () {
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await expect(
      escrow.connect(player1).createMatch(player2Address, tokenAddress, ethers.parseUnits('10', 6), expiresAt)
    )
      .to.emit(escrow, 'MatchCreated')
      .withArgs(1, player1Address, player2Address, tokenAddress, ethers.parseUnits('10', 6), expiresAt);

    const created = await escrow.getMatch(1);
    expect(created.player1).to.equal(player1Address);
    expect(created.player2).to.equal(player2Address);
    expect(created.amount).to.equal(ethers.parseUnits('10', 6));
    expect(created.status).to.equal(0);
  });

  it('rejects createMatch with zero player2 address', async function () {
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await expect(
      escrow.connect(player1).createMatch(ethers.ZeroAddress, tokenAddress, ethers.parseUnits('10', 6), expiresAt)
    ).to.be.revertedWith('invalid player2');
  });

  it('requires both players to deposit and marks match funded', async function () {
    const amount = ethers.parseUnits('5', 6);
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await escrow.connect(player1).createMatch(player2Address, tokenAddress, amount, expiresAt);

    await token.connect(player1).approve(escrowAddress, amount);
    await expect(escrow.connect(player1).deposit(1)).to.emit(escrow, 'Deposited');

    await token.connect(player2).approve(escrowAddress, amount);
    await expect(escrow.connect(player2).deposit(1)).to.emit(escrow, 'MatchFunded');

    expect(await escrow.isMatchFunded(1)).to.be.true;
  });

  it('allows operator to resolve and pays winner minus fee', async function () {
    const amount = ethers.parseUnits('5', 6);
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await escrow.connect(player1).createMatch(player2Address, tokenAddress, amount, expiresAt);

    await token.connect(player1).approve(escrowAddress, amount);
    await escrow.connect(player1).deposit(1);
    await token.connect(player2).approve(escrowAddress, amount);
    await escrow.connect(player2).deposit(1);

    const total = amount * 2n;
    const fee = (total * BigInt(feeBps)) / 10000n;
    const payout = total - fee;
    await expect(escrow.connect(operator).resolveMatch(1, player1Address))
      .to.emit(escrow, 'Resolved')
      .withArgs(1, player1Address, payout, fee);

    const expectedPlayer1 = ethers.parseUnits('1000', 6) - amount + payout;
    expect(await token.balanceOf(player1Address)).to.equal(expectedPlayer1);
    expect(await token.balanceOf(treasuryAddress)).to.equal(fee);
  });

  it('prevents non-operator from resolving matches', async function () {
    const amount = ethers.parseUnits('5', 6);
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await escrow.connect(player1).createMatch(player2Address, tokenAddress, amount, expiresAt);
    await token.connect(player1).approve(escrowAddress, amount);
    await escrow.connect(player1).deposit(1);
    await token.connect(player2).approve(escrowAddress, amount);
    await escrow.connect(player2).deposit(1);

    await expect(
      escrow.connect(other).resolveMatch(1, player1Address)
    ).to.be.revertedWith('operator only');
  });

  it('allows refund after expiry', async function () {
    const amount = ethers.parseUnits('3', 6);
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    await escrow.connect(player1).createMatch(player2Address, tokenAddress, amount, expiresAt);
    await token.connect(player1).approve(escrowAddress, amount);
    await escrow.connect(player1).deposit(1);

    await ethers.provider.send('evm_increaseTime', [7200]);
    await ethers.provider.send('evm_mine');

    await expect(escrow.connect(other).refundMatch(1)).to.emit(escrow, 'Refunded');
    expect(await token.balanceOf(player1Address)).to.equal(ethers.parseUnits('1000', 6));
  });
});
