// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TicTacToeEscrow
 * @dev Non-custodial escrow for TicTacToe betting on Arc testnet.
 *      Players deposit USDC, game resolves winner, operator releases funds + fee.
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract TicTacToeEscrow {
    /// @dev Owner has administrative control (operator, treasury, fee settings)
    address public owner;
    
    /// @dev Operator resolves matches after off-chain validation (Cloud Function)
    address public operator;
    
    /// @dev Treasury receives fees from resolved matches
    address public treasury;
    
    /// @dev Fee in basis points (e.g., 200 = 2%)
    uint256 public feeBps;

    /// @dev Auto-increment match ID counter
    uint256 public nextMatchId;
    
    /// @dev Re-entrancy guard: prevents nested calls to sensitive functions
    uint256 private locked;

    enum Status { Waiting, Funded, Playing, Resolved, Cancelled }

    struct Match {
        address player1;
        address player2;
        address token;
        uint256 amount;
        bool p1Deposited;
        bool p2Deposited;
        Status status;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 depositedTotal;
    }

    mapping(uint256 => Match) public matches;

    event MatchCreated(uint256 indexed matchId, address indexed player1, address indexed player2, address token, uint256 amount, uint256 expiresAt);
    event Deposited(uint256 indexed matchId, address indexed player, uint256 amount);
    event MatchFunded(uint256 indexed matchId);
    event Resolved(uint256 indexed matchId, address indexed winner, uint256 payout, uint256 fee);
    event Refunded(uint256 indexed matchId);
    event OperatorChanged(address indexed oldOp, address indexed newOp);

    modifier onlyOwner() {
        require(msg.sender == owner, "owner only");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "operator only");
        _;
    }
    
    /// @dev Re-entrancy protection (Checks-Effects-Interactions pattern)
    modifier nonReentrant() {
        require(locked == 0, "no re-entrancy");
        locked = 1;
        _;
        locked = 0;
    }

    constructor(address _operator, address _treasury, uint256 _feeBps) {
        require(_operator != address(0), "invalid operator");
        require(_feeBps <= 500, "fee too high"); // Max 5%
        owner = msg.sender;
        operator = _operator;
        treasury = _treasury;
        feeBps = _feeBps;
        nextMatchId = 1;
        locked = 0;
    }

    function setOperator(address _operator) external onlyOwner {
        emit OperatorChanged(operator, _operator);
        operator = _operator;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 500, "fee too high"); // Max 5%
        feeBps = _feeBps;
    }

    function createMatch(address _player2, address _token, uint256 _amount, uint256 _expiresAt) external returns (uint256) {
        require(_player2 != address(0), "invalid player2");
        require(_amount > 0, "amount>0");
        uint256 id = nextMatchId++;
        matches[id] = Match({
            player1: msg.sender,
            player2: _player2,
            token: _token,
            amount: _amount,
            p1Deposited: false,
            p2Deposited: false,
            status: Status.Waiting,
            createdAt: block.timestamp,
            expiresAt: _expiresAt,
            depositedTotal: 0
        });
        emit MatchCreated(id, msg.sender, _player2, _token, _amount, _expiresAt);
        return id;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    /// @dev Deposit USDC stake for a match. Both players must deposit to proceed.
    function deposit(uint256 matchId) external nonReentrant {
        Match storage m = matches[matchId];
        require(m.amount > 0, "match not found");
        require(block.timestamp <= m.expiresAt, "match expired");
        require(m.status == Status.Waiting || m.status == Status.Funded, "invalid status");
        if (msg.sender == m.player1) {
            require(!m.p1Deposited, "already deposited");
            _safeTransferFrom(m.token, msg.sender, address(this), m.amount);
            m.p1Deposited = true;
            m.depositedTotal += m.amount;
            emit Deposited(matchId, msg.sender, m.amount);
        } else if (msg.sender == m.player2) {
            require(!m.p2Deposited, "already deposited");
            _safeTransferFrom(m.token, msg.sender, address(this), m.amount);
            m.p2Deposited = true;
            m.depositedTotal += m.amount;
            emit Deposited(matchId, msg.sender, m.amount);
        } else {
            revert("not a participant");
        }

        if (m.p1Deposited && m.p2Deposited) {
            m.status = Status.Funded;
            emit MatchFunded(matchId);
        }
    }

    function joinMatch(uint256 matchId) external {
        Match storage m = matches[matchId];
        require(m.amount > 0, "match not found");
        require(m.player2 == address(0) || m.player2 == msg.sender, "already assigned");
        m.player2 = msg.sender;
    }

    /// @dev Resolve match and transfer winnings. Only operator can call (off-chain validation).
    /// @param matchId Match ID to resolve
    /// @param winner Address of winning player
    function resolveMatch(uint256 matchId, address winner) external onlyOperator nonReentrant {
        Match storage m = matches[matchId];
        require(m.amount > 0, "match not found");
        require(m.status == Status.Funded || m.status == Status.Playing, "not fundable");
        require(winner == m.player1 || winner == m.player2, "invalid winner");
        require(m.p1Deposited && m.p2Deposited, "not both deposited");

        uint256 total = m.depositedTotal;
        uint256 fee = (total * feeBps) / 10000;
        uint256 payout = total - fee;

        // Update state before transfers (CEI pattern)
        m.status = Status.Resolved;
        
        // Transfer fee to treasury first (smaller amount, safer)
        if (fee > 0 && treasury != address(0)) {
            _safeTransfer(m.token, treasury, fee);
        }
        
        // Transfer payout to winner
        _safeTransfer(m.token, winner, payout);

        emit Resolved(matchId, winner, payout, fee);
    }

    /// @dev Refund deposits if match expires without resolution. Can be called by anyone.
    function refundMatch(uint256 matchId) external nonReentrant {
        Match storage m = matches[matchId];
        require(m.amount > 0, "match not found");
        require(block.timestamp > m.expiresAt, "not expired");
        require(m.status == Status.Waiting || m.status == Status.Funded || m.status == Status.Playing, "cannot refund");
        require(m.depositedTotal > 0, "nothing to refund");

        // Update state before transfers (CEI pattern)
        m.status = Status.Cancelled;
        
        // Refund deposits
        if (m.p1Deposited) {
            _safeTransfer(m.token, m.player1, m.amount);
        }
        if (m.p2Deposited) {
            _safeTransfer(m.token, m.player2, m.amount);
        }
        
        emit Refunded(matchId);
    }

    // owner utility
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function emergencyWithdraw(address token, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "invalid address");
        _safeTransfer(token, to, amount);
    }
    
    //=== VIEW FUNCTIONS ===
    
    /// @dev Get current match details
    function getMatch(uint256 matchId) external view returns (Match memory) {
        return matches[matchId];
    }
    
    /// @dev Check if a match is funded (both players deposited)
    function isMatchFunded(uint256 matchId) external view returns (bool) {
        Match storage m = matches[matchId];
        return m.p1Deposited && m.p2Deposited && m.status == Status.Funded;
    }
}
