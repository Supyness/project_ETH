## Color Grid Game – Minimal MVP

This project contains a Solidity smart contract plus a lightweight HTML front‑end that implements the mechanics described in the prompt:

- Базовый контракт `ColorGridGame` создаёт поле 10×10.
- Цена старта `0.01 ETH`, увеличивается на `3%` после каждого хода.
- Платёж делится `80%` → time bank, `20%` → color bank.
- Time bank доступен последнему игроку, если прошло больше `10 минут` без закрасок.
- Color bank делится между всей “командой цвета” пропорционально числу их ходов, после того как всё поле закрашено одним цветом (pull-модель через `claimColorBank` + `withdrawRewards`).
- Для демо есть контракт `ColorGridGameTest` c полем `2×2` и таймером `5 секунд` — удобно для лабораторных проверок.

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

Deployment outputs the on-chain address. Replace `CONTRACT_ADDRESS` in `frontend/index.html` with that value before using the UI. Чтобы задеплоить тестовую версию на локальную сеть, можно указать имя контракта:

```bash
CONTRACT_NAME=ColorGridGameTest npx hardhat run scripts/deploy.ts --network localhost
```

### Front-end

The `frontend/index.html` file is a static MVP:

1. Serve it locally (e.g. `npx serve frontend` or via any static host).
2. Open it in a browser с установленным MetaMask (или мобильный MetaMask-браузер).
3. Нажмите **Connect Wallet** — фронт прочитает размер сетки/кол-во цветов прямо из контракта, так что UI сам адаптируется под 10×10 или 3×3.
4. Выберите цвет, кликните по ячейке → отправится транзакция `paintCell`.
5. Кнопки “Claim … / Withdraw …” вызывают соответствующие методы, `roundId` для color bank можно подсмотреть через события или `colorWins`.

### Contract overview

`contracts/ColorGridGame.sol` содержит базовый абстрактный контракт `ColorGridGameBase` с параметрами сетки и конкретные реализации:

- `paintCell(cellIndex, colorId)` проверяет цену, обновляет сетку, делит платёж и пишет статистику по раундам.
- `claimTimeBank()` начисляет банк времени последнему игроку (порог — `idleThreshold`, задаётся в конструкторе конкретного контракта).
- `claimColorBank(roundId)` выдаёт долю банка цвета для победившего цвета текущего раунда.
- `withdrawRewards()` отправляет накопленные выигрыши.
- `ColorGridGame` → параметры 10×10 / 10 минут, `ColorGridGameTest` → 3×3 / 5 секунд.

The board resets automatically after a color victory; the price keeps growing globally to make late moves more expensive, exactly as described.

### Next steps

This skeleton intentionally keeps gas usage and UX unoptimized. Potential follow-ups:

- Emit richer events and build a subgraph/off-chain indexer for a real-time leaderboard.
- Limit the max price and/or introduce epochs to prevent runaway cost.
- Swap the vanilla HTML UI for a full React/Next.js front-end with viem/wagmi hooks, server-side caching, etc.
