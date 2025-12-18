// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "hardhat/console.sol";

/**
 * @title ColorGridGameBase
 * @dev Core logic for the painting game. Concrete contracts configure grid size
 *      and idle threshold via the constructor.
 */
abstract contract ColorGridGameBase {
    uint8 private constant EMPTY_COLOR = type(uint8).max;

    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant PRICE_INCREASE_BPS = 300; // 3%
    uint256 private constant TIME_BANK_SHARE_BPS = 8_000; // 80%
    uint256 private constant COLOR_BANK_SHARE_BPS = 2_000; // 20%
    uint256 public constant INITIAL_PRICE = 0.01 ether;

    uint8 public immutable gridSide;
    uint16 public immutable gridCells;
    uint8 public immutable colorCount;
    uint256 public immutable idleThreshold;

    uint256 public currentPrice = INITIAL_PRICE;
    uint256 public timeBank;
    uint256 public colorBank;

    uint256 public lastPaintTimestamp;
    address public lastPainter;

    uint256 public currentRound = 1;
    uint256 public lastColorWinRound;

    uint8[] private _cellColors;
    uint256[] private _cellVersions;
    uint16[] private _colorFillCounts;
    uint256[] private _colorFillVersions;
    uint256 private _boardVersion = 1;
    uint256 private _colorFillVersion = 1;
    uint16 private _filledCells;

    mapping(uint256 => mapping(uint8 => mapping(address => uint256))) public strokesPerRound;
    mapping(uint256 => mapping(uint8 => uint256)) public totalStrokesPerRound;

    mapping(address => uint256) public claimableBalance;

    struct ColorWin {
        uint8 colorId;
        uint256 reward;
        uint256 totalStrokes;
        bool exists;
    }

    mapping(uint256 => ColorWin) public colorWins;
    mapping(uint256 => mapping(address => bool)) public colorRewardClaimed;

    bool private _withdrawLock;

    event CellPainted(address indexed painter, uint8 indexed cellIndex, uint8 indexed colorId, uint256 pricePaid);
    event TimeBankReady(address indexed winner, uint256 reward);
    event ColorBankTriggered(uint256 indexed roundId, uint8 indexed colorId, uint256 reward, uint256 totalStrokes);
    event RewardsWithdrawn(address indexed account, uint256 amount);
    event BoardCleared(address indexed caller);

    constructor(uint8 _gridSide, uint8 _colorCount, uint256 _idleThreshold) {
        require(_gridSide > 0, "Grid side required");
        require(_colorCount > 0, "Color count required");
        require(_idleThreshold > 0, "Idle threshold required");

        gridSide = _gridSide;
        gridCells = uint16(_gridSide) * uint16(_gridSide);
        colorCount = _colorCount;
        idleThreshold = _idleThreshold;

        _cellColors = new uint8[](gridCells);
        _cellVersions = new uint256[](gridCells);
        _colorFillCounts = new uint16[](_colorCount);
        _colorFillVersions = new uint256[](_colorCount);
    }

    modifier validCell(uint8 cellIndex) {
        require(cellIndex < gridCells, "Invalid cell");
        _;
    }

    modifier validColor(uint8 colorId) {
        require(colorId < colorCount, "Invalid color");
        _;
    }

    modifier nonReentrant() {
        require(!_withdrawLock, "Reentrancy");
        _withdrawLock = true;
        _;
        _withdrawLock = false;
    }

    function paintCell(uint8 cellIndex, uint8 colorId)
        external
        payable
        validCell(cellIndex)
        validColor(colorId)
    {
        require(msg.value == currentPrice, "Incorrect payment");

        (uint8 previousColor, bool wasPainted) = _cellState(cellIndex);
        if (wasPainted && previousColor == colorId) {
            revert("Already painted with this color");
        }

        _cellColors[cellIndex] = colorId;
        _cellVersions[cellIndex] = _boardVersion;

        if (!wasPainted) {
            _filledCells += 1;
        } else if (previousColor != EMPTY_COLOR) {
            uint16 prevCount = _getColorFillCount(previousColor);
            _setColorFillCount(previousColor, prevCount - 1);
        }

        uint16 updatedCount = _getColorFillCount(colorId) + 1;
        _setColorFillCount(colorId, updatedCount);

        uint256 timeShare = (msg.value * TIME_BANK_SHARE_BPS) / BASIS_POINTS;
        uint256 colorShare = msg.value - timeShare;
        timeBank += timeShare;
        colorBank += colorShare;

        lastPaintTimestamp = block.timestamp;
        lastPainter = msg.sender;

        strokesPerRound[currentRound][colorId][msg.sender] += 1;
        totalStrokesPerRound[currentRound][colorId] += 1;

        emit CellPainted(msg.sender, cellIndex, colorId, msg.value);

        _increasePrice();

        if (updatedCount == gridCells) {
            _handleColorWin(colorId);
        }
    }

    function canClaimTimeBank() public view returns (bool) {
        return lastPainter != address(0) && timeBank > 0 && block.timestamp >= lastPaintTimestamp + idleThreshold;
    }

    function claimTimeBank() external {
        require(canClaimTimeBank(), "Time bank locked");

        address winner = lastPainter;
        uint256 reward = timeBank;
        timeBank = 0;

        claimableBalance[winner] += reward;
        emit TimeBankReady(winner, reward);
    }

    function claimColorBank(uint256 roundId) external {
        ColorWin memory win = colorWins[roundId];
        require(win.exists, "Round missing");
        require(!colorRewardClaimed[roundId][msg.sender], "Already claimed");

        uint256 contributorStrokes = strokesPerRound[roundId][win.colorId][msg.sender];
        require(contributorStrokes > 0, "No contribution");

        uint256 payout = (win.reward * contributorStrokes) / win.totalStrokes;
        colorRewardClaimed[roundId][msg.sender] = true;

        claimableBalance[msg.sender] += payout;
    }

    function withdrawRewards() external nonReentrant {
        uint256 amount = claimableBalance[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        claimableBalance[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit RewardsWithdrawn(msg.sender, amount);
    }

    function getBoard() external view returns (uint8[] memory board) {
        board = new uint8[](_cellColors.length);
        for (uint256 i = 0; i < board.length; i++) {
            if (_cellVersions[i] == _boardVersion) {
                board[i] = _cellColors[i];
            } else {
                board[i] = EMPTY_COLOR;
            }
        }
    }

    function getColorFillCounts() external view returns (uint16[] memory counts) {
        counts = new uint16[](_colorFillCounts.length);
        for (uint256 c = 0; c < counts.length; c++) {
            if (_colorFillVersions[c] == _colorFillVersion) {
                counts[c] = _colorFillCounts[c];
            }
        }
    }

    function clearBoard() external {
        require(_filledCells > 0, "Board already empty");

        _resetBoard();
        emit BoardCleared(msg.sender);
    }

    function _handleColorWin(uint8 winningColor) private {
        uint256 reward = colorBank;
        require(reward > 0, "Color bank empty");

        uint256 totalStrokes = totalStrokesPerRound[currentRound][winningColor];
        require(totalStrokes > 0, "No strokes for color");

        colorBank = 0;
        colorWins[currentRound] = ColorWin({
            colorId: winningColor,
            reward: reward,
            totalStrokes: totalStrokes,
            exists: true
        });

        lastColorWinRound = currentRound;
        emit ColorBankTriggered(currentRound, winningColor, reward, totalStrokes);

        currentRound += 1;
        _resetBoard();
    }

    function _resetBoard() private {
        _boardVersion += 1;
        _colorFillVersion += 1;
        _filledCells = 0;
    }

    function _increasePrice() private {
        currentPrice = (currentPrice * (BASIS_POINTS + PRICE_INCREASE_BPS)) / BASIS_POINTS;
    }

    function _cellState(uint256 cellIndex) private view returns (uint8 colorId, bool painted) {
        console.log("1");
        painted = _cellVersions[cellIndex] == _boardVersion;
        colorId = painted ? _cellColors[cellIndex] : EMPTY_COLOR;
    }

    function _getColorFillCount(uint8 colorId) private view returns (uint16) {
        if (_colorFillVersions[colorId] != _colorFillVersion) {
            return 0;
        }
        return _colorFillCounts[colorId];
    }

    function _setColorFillCount(uint8 colorId, uint16 value) private {
        _colorFillVersions[colorId] = _colorFillVersion;
        _colorFillCounts[colorId] = value;
    }
}

contract ColorGridGame is ColorGridGameBase {
    constructor() ColorGridGameBase(10, 10, 10 minutes) {}
}

contract ColorGridGameTest is ColorGridGameBase {
    constructor() ColorGridGameBase(2, 10, 5 seconds) {}
}
