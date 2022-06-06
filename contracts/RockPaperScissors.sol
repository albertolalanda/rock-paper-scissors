// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.7;

contract RockPaperScissors {

    /**
     * @notice Possible moves for the game
     * Rock - 0
     * Paper - 1
     * Scissors - 2
     */
    enum PlayerMove {
        Rock,
        Paper,
        Scissors
    }

    /**
     * Stopped - 0
     * WaitingForPlayerTwo - 1
     * WaitingForReveal - 2
     * WaitingForCompletion - 3
     */
    enum GameState {
        Stopped,
        WaitingForPlayerTwo,
        WaitingForReveal,
        WaitingForCompletion
    }

    int8[3][3] checkWinner = [
        [int8(0), int8(-1), int8(1)],
        [int8(1), int8(0), int8(-1)],
        [int8(-1), int8(1), int8(0)]
    ];

    /**
     * @notice Event emitted when a player submits or reveals a move
     * @param gameState The submitted or revealed move
     */
    event State(GameState gameState);

    /**
     * @notice Event emitted when a player submits or reveals a move
     * @param player The address of the player making or revealing the move
     * @param move The submitted or revealed move
     */
    event Move(address player, PlayerMove move);

    /**
     * @notice Event emitted when a player wins the game due to their move
     * @param winner The winning player's address
     * @param amount The amount of coins won
     */
    event Winner(address winner, uint256 amount);

    /**
     * @notice Event emitted when the game results in a tie
     * @param playerOne The first player's address
     * @param playerTwo The second player's address
     * @param amount The amount of coins divided among both players
     */
    event Tie(address playerOne, address playerTwo, uint256 amount);

    /**
     * @notice Event emitted when the game ends due to a timeout
     * @param winner The address of the player winning due to the timeout
     * @param amount The amount of coins won
     */
    event TimeOut(address winner, uint256 amount);

    /**
     * @notice The timeout (in seconds) after which the game can be completed without waiting for the opponent's action
     */
    uint public timeout;

    /**
     * @notice The minimum amount to bet when starting a new game
     */
    uint public minimumBet;

    /**
     * @notice The safety deposit to be made by Player One. Will be refunded when the move is revealed.
     */
    uint public playerOneDeposit;

    mapping(address => uint256) public balances;

    GameState public gameState;
    uint256 lastActionTimestamp;

    /**
     * @notice The pot, i.e. the amount of money that can be won
     */
    uint256 public potSize;

    /**
     * @notice The bet, i.e. the amount of money that needs to be sent to join the game
     */
    uint256 public betSize;

    address public playerOne;
    bytes32 hiddenMovePlayerOne;
    PlayerMove public movePlayerOne;

    address public playerTwo;
    PlayerMove public movePlayerTwo;

    /**
     * @notice Accepts coins to add to the pot. Sender is not registered as a player!
     */
    receive() external payable {
        potSize += msg.value;
    }

    constructor(uint256 _timeout, uint256 _minimumBet, uint256 _playerOneDeposit)  { 
        timeout = _timeout;
        minimumBet = _minimumBet;
        playerOneDeposit = _playerOneDeposit;
    }

    function startGame(bytes32 hiddenMove) external payable {
        require(gameState == GameState.Stopped, "A game is already running!");
        require(msg.value >= minimumBet + playerOneDeposit, "Not enough coins sent for minimum bet and deposit!");
        
        betSize = msg.value - playerOneDeposit;
        potSize += betSize;
        playerOne = msg.sender;
        hiddenMovePlayerOne = hiddenMove;

        setGameState(GameState.WaitingForPlayerTwo);
    }

    function joinGame(PlayerMove move) external payable {

        require(gameState == GameState.WaitingForPlayerTwo, "Cannot join a game when it is not waiting for a second player!");
        require(msg.value == betSize, "Please supply exactly `betSize` coins!");
        require(msg.sender != playerOne, "Cannot play against yourself!");

        potSize += msg.value;
        playerTwo = msg.sender;
        movePlayerTwo = move;

        emit Move(msg.sender, move);

        setGameState(GameState.WaitingForReveal);
    }

    function revealMove(PlayerMove move, uint256 nonce) external  {
        require(gameState == GameState.WaitingForReveal, "Cannot reveal the move when the game is not waiting for a reveal!");

        bytes32 hashed = getMessageHash(move, nonce);
        assert(hashed == hiddenMovePlayerOne);
        movePlayerOne = move;
        balances[playerOne] += playerOneDeposit;

        emit Move(playerOne, move);

        setGameState(GameState.WaitingForCompletion);

        completeGame();
    }

    function completeGame() public {
        require(gameState != GameState.Stopped, "Cannot complete a game when none is running!");

        if (gameState == GameState.WaitingForPlayerTwo) {
            require(isTimedOut(), "Cannot complete a game without a second player before the timeout!");

            balances[playerOne] += potSize;
            balances[playerOne] += playerOneDeposit;

            emit TimeOut(playerOne, potSize);
        }
        else if (gameState == GameState.WaitingForReveal) {
            require(isTimedOut(), "Cannot complete a game waiting for reveal before the timeout!");

            balances[playerTwo] += potSize;
            balances[playerTwo] += playerOneDeposit;

            emit TimeOut(playerTwo, potSize);
        } else if (gameState == GameState.WaitingForCompletion) {
            int8 winner = checkWinner[uint(movePlayerOne)][uint(movePlayerTwo)];

            if (winner > 0) {
                balances[playerOne] += potSize;

                emit Winner(playerOne, potSize);
            } else if (winner < 0) {
                balances[playerTwo] += potSize;

                emit Winner(playerTwo, potSize);
            } else {
                balances[playerOne] += potSize / 2;
                balances[playerTwo] += potSize / 2;

                emit Tie(playerOne, playerTwo, potSize);
            }
        } else {
            revert("Invalid game state!");
        }

        delete potSize;
        delete betSize;
        delete playerOne;
        delete hiddenMovePlayerOne;
        delete movePlayerOne;
        delete playerTwo;
        delete movePlayerTwo;

        setGameState(GameState.Stopped);
    }

    /**
     * @notice Withdraws coins from the sender's internal balance
     * @param target The address to send coins to
     */
    function withdraw(address target) external {
        require(balances[msg.sender] > 0, "Cannot withdraw without a balance!");

        uint256 balanceToTransfer = balances[msg.sender];
        balances[msg.sender] = 0;
        (bool success,) = target.call{value: balanceToTransfer}("");

        if (!success) {
            balances[msg.sender] = balanceToTransfer;
        }
    }

    function getGameState() external returns (GameState) {
        emit State(gameState);
        return gameState;
    }

    function getMinimumBet() external view returns (uint) {
        return minimumBet;
    }

    function setGameState(GameState newState) private {
        gameState = newState;
        lastActionTimestamp = block.timestamp;
        emit State(gameState);
    }


    /**
     * @notice Specifies when a game can be completed due to a timeout
     * @return The UNIX timestamp at which the game can be completed
     */
    function timeoutAt() public view returns (uint256) {
        return lastActionTimestamp + timeout;
    }

    function isTimedOut() private view returns (bool) {
        return block.timestamp >= timeoutAt();
    }

    function getMessageHash(PlayerMove _move, uint256 _nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(_move, _nonce));
    }

}
