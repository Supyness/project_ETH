## Color Grid Game – Minimal MVP

This project contains a Solidity smart contract plus a lightweight HTML front‑end that implements the mechanics described in the prompt:

- The base contract `ColorGridGame` creates a 10x10 grid.
- The starting price is `0.01 ETH`, increasing by `3%` after each move.
- The payment is divided 80% → time bank, 20% → color bank.
- The time bank is available to the last player if more than `10 minutes` have passed without any coloring.
- The color bank is divided among the entire “color team” proportionally to the number of their moves, after the entire field is painted with one color (pull model via `claimColorBank` + `withdrawRewards`).
- For the demo, there is a `ColorGridGameTest` contract with a `2x2` field and a `5 seconds` timer - convenient for lab tests.

### Prerequisites

The repo was prepared for the Hardhat + TypeScript toolchain. Install dependencies once:

```bash
npm install
```

Copy `.env.example` to `.env` and provide RPC + private key/etherscan token as needed.

### Useful commands

```bash
npm run compile      # compile the Solidity contracts
npm test             # run the unit tests
npm run deploy       # deploy to Sepolia (configure .env first)
```

Deployment outputs the on-chain address. Replace `CONTRACT_ADDRESS` in `frontend/index.html` with that value before using the UI. To deploy a test version to a local network, you can specify the contract name:

```bash
CONTRACT_NAME=ColorGridGameTest npx hardhat run scripts/deploy.ts --network localhost
```

### Front-end

The `frontend/index.html` file is a static MVP:

1. Serve it locally (e.g. `npx serve frontend` or via any static host).
2. Open it in a browser with MetaMask installed (or the MetaMask mobile browser).
3. Click **Connect Wallet** - the frontend will read the grid size/number of colors directly from the contract, so the UI itself will adapt to 10x10 or 3x3.
4. Select a color, click on the cell → the `paintCell` transaction will be sent.
5. The “Claim … / Withdraw …” buttons call the corresponding methods, the `roundId` for the color bank can be found through events or `colorWins`.

### Contract overview

`contracts/ColorGridGame.sol` contains the base abstract contract `ColorGridGameBase` with grid parameters and concrete implementations:

- `paintCell(cellIndex, colorId)` checks the price, updates the grid, divides the payment and writes statistics for the rounds.
- `claimTimeBank()` credits the time bank to the last player (the threshold is `idleThreshold`, set in the constructor of a specific contract).
- `claimColorBank(roundId)` returns the color bank share for the winning color of the current round.
- `withdrawRewards()` sends accumulated winnings.
- `ColorGridGame` → parameters 10×10 / 10 minutes, `ColorGridGameTest` → 3×3 / 5 seconds.

The board resets automatically after a color victory; the price keeps growing globally to make late moves more expensive, exactly as described.
