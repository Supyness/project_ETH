import { expect } from "chai";
import { ethers } from "hardhat";

describe("ColorGridGame", () => {
  async function deploy() {
    const [owner, other] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("ColorGridGame");
    const game = await factory.deploy();
    await game.waitForDeployment();
    return { game, owner, other };
  }

  it("increments price and allocates banks after painting", async () => {
    const { game, owner } = await deploy();
    const firstPrice = await game.currentPrice();
    await expect(game.paintCell(0, 0, { value: firstPrice }))
      .to.emit(game, "CellPainted")
      .withArgs(owner.address, 0, 0, firstPrice);

    const updatedPrice = await game.currentPrice();
    expect(updatedPrice).to.gt(firstPrice);

    const timeBank = await game.timeBank();
    const colorBank = await game.colorBank();
    expect(timeBank).to.eq(firstPrice * 8n / 10n);
    expect(colorBank).to.eq(firstPrice - timeBank);
  });

  it("allows claiming the time bank after inactivity", async () => {
    const { game, owner } = await deploy();
    const price = await game.currentPrice();
    await game.paintCell(0, 0, { value: price });

    await ethers.provider.send("evm_increaseTime", [10 * 60 + 1]);
    await ethers.provider.send("evm_mine", []);

    await game.claimTimeBank();

    const claimable = await game.claimableBalance(owner.address);
    const expectedReward = (price * 8n) / 10n;
    expect(claimable).to.eq(expectedReward);

    await expect(game.withdrawRewards())
      .to.emit(game, "RewardsWithdrawn")
      .withArgs(owner.address, claimable);
  });

  it("distributes color bank when full board shares a color", async () => {
    const { game, owner, other } = await deploy();
    const gridCells = Number(await game.gridCells());

    const cutoff = Math.floor(gridCells * 0.7);
    for (let i = 0; i < gridCells; i++) {
      const price = await game.currentPrice();
      const painter = i < cutoff ? owner : other;
      await game.connect(painter).paintCell(i, 1, { value: price });
    }

    const win = await game.colorWins(1);
    expect(win.exists).to.eq(true);
    expect(win.colorId).to.eq(1);
    expect(win.totalStrokes).to.eq(gridCells);
    expect(await game.lastColorWinRound()).to.eq(1);

    await expect(game.connect(owner).claimColorBank(1)).to.not.be.reverted;
    await expect(game.connect(other).claimColorBank(1)).to.not.be.reverted;

    const ownerShare = await game.claimableBalance(owner.address);
    const otherShare = await game.claimableBalance(other.address);

    expect(ownerShare).to.be.gt(otherShare);
    expect(ownerShare + otherShare).to.be.closeTo(win.reward, 1n);
  });
});

describe("ColorGridGameTest variant", () => {
  it("uses 2x2 grid and 5-second time bank threshold", async () => {
    const [owner] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("ColorGridGameTest");
    const game = await factory.deploy();
    await game.waitForDeployment();

    expect(Number(await game.gridSide())).to.eq(2);
    expect(Number(await game.gridCells())).to.eq(4);

    const price = await game.currentPrice();
    await game.paintCell(0, 0, { value: price });

    await ethers.provider.send("evm_increaseTime", [6]);
    await ethers.provider.send("evm_mine", []);

    await expect(game.claimTimeBank()).to.not.be.reverted;

    const idleReward = await game.claimableBalance(owner.address);
    expect(idleReward).to.eq((price * 8n) / 10n);
  });
});
