// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// OpenZeppelin upgradeable contracts for proxy pattern and security
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interface/IDBCAIContract.sol";

import "forge-std/console.sol";

// OpenZeppelin upgradeable access control and proxy utilities
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// Custom libraries for reward calculation and utility functions
import { RewardCalculatorLib } from "./library/RewardCalculatorLib.sol";
import { ToolLib } from "./library/ToolLib.sol";

// Math utilities and safe token transfers
import "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Custom types for staking system
import { StakingType, MachineStatus, NotifyType } from "./types.sol";

/**
 * @title NFTStaking
 * @dev A comprehensive NFT staking contract for GPU mining rewards
 * @notice This contract allows users to stake NFTs representing GPU machines and earn rewards
 * @custom:oz-upgrades-from OldNFTStaking
 */
contract NFTStaking is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC1155Receiver
{
    // ============ Constants ============
    /// @notice Average seconds per block in the blockchain
    uint8 public constant SECONDS_PER_BLOCK = 6;
    /// @notice Base reserve amount required for staking (100,000 DBC)
    uint256 public constant BASE_RESERVE_AMOUNT = 100_000 ether;
    /// @notice Maximum number of NFTs that can be staked per machine
    uint8 public constant MAX_NFTS_PER_MACHINE = 10;
    /// @notice Lock period for rewards (180 days)
    uint256 public constant LOCK_PERIOD = 180 days;
    /// @notice Type of staking (Free staking)
    StakingType public constant STAKING_TYPE = StakingType.Free;
    /// @notice Amount to be slashed for violations (100,000 DBC)
    uint256 public constant SLASH_AMOUNT = 100_000 ether;

    // ============ External Contracts ============
    /// @notice DBC AI contract interface for machine management
    IDBCAIContract public dbcAIContract;
    /// @notice ERC1155 NFT token contract representing GPU machines
    IERC1155 public nftToken;
    /// @notice ERC20 reward token contract (DBC tokens)
    IERC20 public rewardToken;

    // ============ Administrative Addresses ============
    /// @notice Address authorized to upgrade the contract
    address public canUpgradeAddress;
    /// @notice Address to receive slashed tokens
    address public slashToAddress;
    
    // ============ Reward System State ============
    /// @notice Total amount of rewards distributed so far
    uint256 public totalDistributedRewardAmount;
    /// @notice Timestamp when reward distribution starts
    uint256 public rewardStartAtTimestamp;
    /// @notice Total number of GPUs in the system
    uint256 public totalGpuCount;
    /// @notice Total amount reserved across all stakes
    uint256 public totalReservedAmount;
    /// @notice Total calculation points across all staked machines
    uint256 public totalCalcPoint;
    /// @notice Name of the project
    string public projectName;
    /// @notice Whether the contract is registered
    bool public registered;
    /// @notice Total adjustment units for reward calculation
    uint256 public totalAdjustUnit;
    /// @notice Daily reward amount distributed
    uint256 public dailyRewardAmount;
    /// @notice Total number of GPUs currently staking
    uint256 public totalStakingGpuCount;

    RewardCalculatorLib.RewardsPerShare public rewardsPerCalcPoint;

    string[] public stakedMachineIds;

    // ============ Data Structures ============
    
    /**
     * @dev Details of locked rewards for a machine
     * @param totalAmount Total amount of locked rewards
     * @param lockTime Timestamp when rewards were locked
     * @param unlockTime Timestamp when rewards can be unlocked
     * @param claimedAmount Amount already claimed from locked rewards
     */
    struct LockedRewardDetail {
        uint256 totalAmount;
        uint256 lockTime;
        uint256 unlockTime;
        uint256 claimedAmount;
    }

    /**
     * @dev Information about approved report
     * @param renter Address of the renter who made the report
     */
    struct ApprovedReportInfo {
        address renter;
    }

    /**
     * @dev Information about a staked machine
     * @param holder Address of the user who staked the machine
     * @param startAtTimestamp Timestamp when staking started
     * @param lastClaimAtTimestamp Timestamp of the last reward claim
     * @param calcPoint Calculation points for reward distribution
     * @param reservedAmount Amount of tokens reserved for this stake
     * @param nftTokenIds Array of NFT token IDs representing the machine
     * @param tokenIdBalances Array of balances for each NFT token ID
     * @param nftCount Total number of NFTs staked
     * @param claimedAmount Total amount of rewards claimed
     * @param gpuCount Number of GPUs in this machine
     */
    struct StakeInfo {
        address holder;
        uint256 startAtTimestamp;
        uint256 lastClaimAtTimestamp;
        uint256 calcPoint;
        uint256 reservedAmount;
        uint256[] nftTokenIds;
        uint256[] tokenIdBalances;
        uint256 nftCount;
        uint256 claimedAmount;
        uint256 gpuCount;
    }

    // ============ Storage Mappings ============
    
    /// @notice Mapping to track valid wallet addresses for admin operations
    mapping(address => bool) public validWalletAddress;
    /// @notice Mapping from holder address to their staked machine IDs
    mapping(address => string[]) public holder2MachineIds;
    /// @notice Mapping from machine ID to array of locked reward details
    mapping(string => LockedRewardDetail[]) public machineId2LockedRewardDetails;
    /// @notice Mapping from machine ID to its staking information
    mapping(string => StakeInfo) public machineId2StakeInfos;
    /// @notice Mapping from machine ID to its locked reward details
    mapping(string => LockedRewardDetail) public machineId2LockedRewardDetail;
    /// @notice Mapping from machine ID to its reward calculation state
    mapping(string => RewardCalculatorLib.UserRewards) public machineId2StakeUnitRewards;
    /// @notice Private mapping to track which machines are staked
    mapping(string => bool) private stakedMachinesMap;
    /// @notice Mapping to track machines pending slash
    mapping(string => bool) public pendingSlashedMachine;
    /// @notice Mapping to track machines currently working
    mapping(string => bool) public inWorkingMachine;

    // ============ Events ============
    
    /**
     * @dev Emitted when a machine is staked
     * @param stakeholder Address of the user who staked
     * @param machineId Unique identifier of the machine
     * @param originCalcPoint Original calculation points before NFT multiplier
     * @param calcPoint Final calculation points after NFT multiplier
     */
    event Staked(address indexed stakeholder, string machineId, uint256 originCalcPoint, uint256 calcPoint);

    /**
     * @dev Emitted when GPU type information is recorded for a staked machine
     * @param machineId Unique identifier of the machine
     * @param gpuType Type of GPU in the machine
     */
    event StakedGPUType(string machineId, string gpuType);

    /// @dev Emitted when DLC tokens are reserved for a machine
    event ReserveDLC(string machineId, uint256 amount);
    
    /**
     * @dev Emitted when a machine is unstaked
     * @param stakeholder Address of the user who unstaked
     * @param machineId Unique identifier of the machine
     * @param paybackReserveAmount Amount of reserved tokens returned
     */
    event Unstaked(address indexed stakeholder, string machineId, uint256 paybackReserveAmount);
    
    /**
     * @dev Emitted when rewards are claimed
     * @param stakeholder Address of the stakeholder claiming rewards
     * @param machineId Unique identifier of the machine
     * @param lockedRewardAmount Amount of rewards locked
     * @param moveToUserWalletAmount Amount transferred to user wallet
     * @param moveToReservedAmount Amount moved to reserved balance
     */
    event Claimed(
        address indexed stakeholder,
        string machineId,
        uint256 lockedRewardAmount,
        uint256 moveToUserWalletAmount,
        uint256 moveToReservedAmount
    );

    /// @dev Emitted when slash payment is processed
    event PaySlash(string machineId, uint256 slashAmount);
    /// @dev Emitted when a machine fault is reported
    event ReportMachineFault(string machineId, address renter);
    /// @dev Emitted when rewards per calculation point is updated
    event RewardsPerCalcPointUpdate(uint256 accumulatedPerShareBefore, uint256 accumulatedPerShareAfter);
    /// @dev Emitted when amount is moved to reserve
    event MoveToReserveAmount(string machineId, address holder, uint256 amount);
    /// @dev Emitted when rent is renewed
    event RenewRent(string machineId, address holder, uint256 rentFee);
    /// @dev Emitted when a machine is unregistered
    event MachineUnregistered(string machineId);
    /// @dev Emitted when a machine is registered
    event MachineRegistered(string machineId);
    /// @dev Emitted when a machine exits staking due to being offline
    event ExitStakingForOffline(string machineId, address holder);
    /// @dev Emitted when rewarding is recovered for a machine
    event RecoverRewarding(string machineId, address holder);
    /// @dev Emitted when machine working status is set
    event SetMachineWorking(string machineId, bool isWorking);

    // ============ Custom Errors ============
    
    /// @dev Thrown when reward distribution has not started yet
    error RewardNotStart();
    /// @dev Thrown when caller is not the authorized rent contract
    error CallerNotRentContract();
    /// @dev Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();
    /// @dev Thrown when trying to add an address that already exists
    error AddressExists();
    /// @dev Thrown when the caller is not authorized to upgrade the contract
    error CanNotUpgrade(address);
    /// @dev Thrown when provided timestamp is less than current timestamp
    error TimestampLessThanCurrent();
    /// @dev Thrown when trying to operate on a machine that is not staked
    error MachineNotStaked(string machineId);
    /// @dev Thrown when trying to stake a machine that is already staking
    error MachineIsStaking(string machineId);
    /// @dev Thrown when machine memory size is less than 16GB
    error MemorySizeLessThan16G(uint256 mem);
    /// @dev Thrown when GPU type does not match expected format
    error GPUTypeNotMatch(string gpuType);
    /// @dev Thrown when calculation point is zero
    error ZeroCalcPoint();
    /// @dev Thrown when NFT token ID and balance arrays have different lengths
    error InvalidNFTLength(uint256 tokenIdLength, uint256 balanceLength);
    /// @dev Thrown when caller is not the machine owner
    error NotMachineOwner(address);
    /// @dev Thrown when no NFT token IDs are provided
    error ZeroNFTTokenIds();
    /// @dev Thrown when NFT count exceeds maximum allowed (20)
    error NFTCountGreaterThan20();
    /// @dev Thrown when trying to claim before paying required slash amount
    error NotPaidSlashBeforeClaim(string machineId, uint256 slashAmount);
    /// @dev Thrown when caller is not the stake holder of the machine
    error NotStakeHolder(string machineId, address currentAddress);
    /// @dev Thrown when machine is currently rented by a user
    error MachineRentedByUser();
    /// @dev Thrown when machine is not rented
    error MachineNotRented();
    /// @dev Thrown when caller is not an admin
    error NotAdmin();
    /// @dev Thrown when machine does not have enough DBC staked
    error MachineNotStakeEnoughDBC();
    /// @dev Thrown when machine is not online or not registered
    error MachineNotOnlineOrRegistered();
    /// @dev Thrown when caller is neither machine owner nor admin
    error NotMachineOwnerOrAdmin();
    /// @dev Thrown when machine is still registered and cannot be unstaked
    error MachineStillRegistered();
    /// @dev Thrown when trying to operate on long-term staking
    error StakingInLongTerm();
    /// @dev Thrown when machine is currently staking
    error IsStaking();
    /// @dev Thrown when there are not enough rewards available
    error RewardNotEnough();
    /// @dev Thrown when total rate does not equal 100%
    error TotalRateNotEq100();
    /// @dev Thrown when caller is not the DBC AI contract
    error NotDBCAIContract();

    /**
     * @dev Constructor that disables initializers to prevent implementation contract initialization
     * @notice This is required for UUPS upgradeable contracts
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Handles batch receipt of ERC1155 tokens
     * @return bytes4 The function selector to confirm token transfer
     */
    function onERC1155BatchReceived(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Handles single receipt of ERC1155 tokens
     * @return bytes4 The function selector to confirm token transfer
     */
    function onERC1155Received(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256, /* unusedParameter */
        uint256, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Checks if the contract supports a given interface
     * @param interfaceId The interface identifier to check
     * @return bool True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ============ Modifiers ============
    
    /**
     * @dev Ensures that only valid wallet addresses or the owner can call the function
     * @notice Reverts if the caller is not in the valid wallet list and not the owner
     */
    modifier onlyValidWallet() {
        require(validWalletAddress[msg.sender] || msg.sender == owner(), NotAdmin());
        _;
    }

    /**
     * @dev Ensures that only the DBC AI contract can call the function
     * @notice Reverts if the caller is not the authorized DBC AI contract
     */
    modifier onlyDBCAIContract() {
        require(msg.sender == address(dbcAIContract), NotDBCAIContract());
        _;
    }

    /**
     * @dev Ensures that a machine can be staked with the provided parameters
     * @param stakeholder The address of the user staking the machine
     * @param machineId The unique identifier of the machine to check
     * @param nftTokenIds Array of NFT token IDs to stake
     * @param nftTokenIdBalances Array of balances for each NFT token ID
     * @notice Reverts if the machine cannot be staked due to various conditions
     */
    modifier canStake(
        address stakeholder,
        string memory machineId,
        uint256[] memory nftTokenIds,
        uint256[] memory nftTokenIdBalances
    ) {
        require(rewardStartAtTimestamp > 0, RewardNotStart());
        require(validWalletAddress[msg.sender], NotAdmin());
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.nftTokenIds.length == 0, IsStaking());
        require(dbcAIContract.freeGpuAmount(machineId) >= 1, MachineNotStakeEnoughDBC());
        require(
            nftTokenIds.length == nftTokenIdBalances.length,
            InvalidNFTLength(nftTokenIds.length, nftTokenIdBalances.length)
        );

        (bool isOnline, bool isRegistered) = dbcAIContract.getMachineState(machineId, projectName, STAKING_TYPE);
        require(isOnline && isRegistered, MachineNotOnlineOrRegistered());
        require(!isStaking(machineId), MachineIsStaking(machineId));
        require(nftTokenIds.length > 0, ZeroNFTTokenIds());
        _;
    }

    /**
     * @dev Initializes the contract with required parameters
     * @param _initialOwner The initial owner of the contract
     * @param _nftToken The ERC1155 NFT token contract address
     * @param _rewardToken The ERC20 reward token contract address
     * @param _dbcAIContract The DBC AI contract address
     * @param _slashToAddress The address to receive slashed tokens
     * @param _projectName The name of the project
     */
    function initialize(
        address _initialOwner,
        address _nftToken,
        address _rewardToken,
        address _dbcAIContract,
        address _slashToAddress,
        string memory _projectName
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        rewardToken = IERC20(_rewardToken);
        nftToken = IERC1155(_nftToken);
        dbcAIContract = IDBCAIContract(_dbcAIContract);

        projectName = _projectName;
        slashToAddress = _slashToAddress;

        dailyRewardAmount = uint256(50_000_000_000 ether) / 365;

        canUpgradeAddress = msg.sender;
        rewardsPerCalcPoint.lastUpdated = block.timestamp;
        rewardStartAtTimestamp = block.timestamp;
    }


    // ============ Admin Functions ============
    
    /**
     * @dev Authorizes contract upgrades (UUPS pattern)
     * @param newImplementation The address of the new implementation contract
     * @notice Only the contract owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    /**
     * @dev Sets the upgrade address for the contract
     * @param addr The address authorized to upgrade the contract
     * @notice Only the contract owner can set upgrade address
     */
    function setUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    /**
     * @dev Sets the reward token contract address
     * @param token The address of the ERC20 reward token contract
     * @notice Only the contract owner can set the reward token
     */
    function setRewardToken(address token) external onlyOwner {
        rewardToken = IERC20(token);
    }

    /**
     * @dev Sets the NFT token contract address
     * @param token The address of the ERC1155 NFT token contract
     * @notice Only the contract owner can set the NFT token
     */
    function setNftToken(address token) external onlyOwner {
        nftToken = IERC1155(token);
    }

    /**
     * @dev Sets the timestamp when reward distribution starts
     * @param timestamp The timestamp when rewards begin
     * @notice Only the contract owner can set the reward start time
     */
    function setRewardStartAt(uint256 timestamp) external onlyOwner {
        require(timestamp >= block.timestamp, TimestampLessThanCurrent());
        rewardStartAtTimestamp = timestamp;
    }

    /**
     * @dev Adds valid wallet addresses that can interact with the contract
     * @param addrs Array of wallet addresses to add as valid
     * @notice Only the contract owner can add valid wallets
     */
    function setDLCClientWallets(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            require(addrs[i] != address(0), ZeroAddress());
            require(validWalletAddress[addrs[i]] == false, AddressExists());
            validWalletAddress[addrs[i]] = true;
        }
    }

    /**
     * @dev Sets the DBC AI contract address
     * @param addr The address of the DBC AI contract
     * @notice Only the contract owner can set the DBC AI contract
     */
    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    /**
     * @dev Adds additional tokens to an existing staked machine
     * @param machineId The unique identifier of the machine
     * @param amount The amount of tokens to add to the stake
     * @notice Only callable when the machine is already staking
     */
    function addTokenToStake(string memory machineId, uint256 amount) external nonReentrant {
        require(isStaking(machineId), MachineNotStaked(machineId));
        if (amount == 0) {
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        _joinStaking(machineId, stakeInfo.calcPoint, amount + stakeInfo.reservedAmount);
        emit ReserveDLC(machineId, amount);
    }

    /**
     * @dev Internal function to validate machine specifications for staking
     * @param calcPoint The calculation points of the machine
     * @param gpuType The GPU type string of the machine
     * @param mem The memory size of the machine in GB
     * @notice Reverts if machine specifications don't meet staking requirements
     */
    function revertIfMachineInfoCanNotStake(uint256 calcPoint, string memory gpuType, uint256 mem) internal pure {
        require(mem >= 16, MemorySizeLessThan16G(mem));
        require(ToolLib.checkString(gpuType), GPUTypeNotMatch(gpuType));
        require(calcPoint > 0, ZeroCalcPoint());
    }

    /**
     * @dev Initializes locked reward information for a machine if not already set
     * @param machineId The unique identifier of the machine
     * @param currentTime The current timestamp to use for lock calculations
     * @notice Only initializes if the machine doesn't have existing lock info
     */
    function _tryInitMachineLockRewardInfo(string memory machineId, uint256 currentTime) internal {
        if (machineId2LockedRewardDetail[machineId].lockTime == 0) {
            machineId2LockedRewardDetail[machineId] = LockedRewardDetail({
                totalAmount: 0,
                lockTime: currentTime,
                unlockTime: currentTime + LOCK_PERIOD,
                claimedAmount: 0
            });
        }
    }

    /**
     * @dev Stakes NFTs representing GPU machines to earn rewards
     * @param stakeholder The address of the user staking the machine
     * @param machineId The unique identifier of the machine to stake
     * @param nftTokenIds Array of NFT token IDs to stake
     * @param nftTokenIdBalances Array of balances for each NFT token ID
     */
    function stake(
        address stakeholder,
        string calldata machineId,
        uint256[] calldata nftTokenIds,
        uint256[] calldata nftTokenIdBalances
    ) external onlyValidWallet canStake(stakeholder, machineId, nftTokenIds, nftTokenIdBalances) nonReentrant {
        (address machineOwner, uint256 calcPoint,, string memory gpuType,,,,, uint256 mem) =
            dbcAIContract.getMachineInfo(machineId, true);
        require(machineOwner == stakeholder, NotMachineOwner(machineOwner));
        revertIfMachineInfoCanNotStake(calcPoint, gpuType, mem);

        uint256 nftCount = getNFTCount(nftTokenIdBalances);
        require(nftCount <= MAX_NFTS_PER_MACHINE, NFTCountGreaterThan20());
        uint256 originCalcPoint = calcPoint;
        calcPoint = calcPoint * nftCount;
        uint256 currentTime = block.timestamp;

        uint8 gpuCount = 1;
        if (!stakedMachinesMap[machineId]) {
            stakedMachinesMap[machineId] = true;
            totalGpuCount += gpuCount;
        }

        totalStakingGpuCount += gpuCount;

        StakeInfo storage oldStakeInfo = machineId2StakeInfos[machineId];
        nftToken.safeBatchTransferFrom(stakeholder, address(this), nftTokenIds, nftTokenIdBalances, "transfer");
        machineId2StakeInfos[machineId] = StakeInfo({
            startAtTimestamp: currentTime,
            lastClaimAtTimestamp: currentTime,
            calcPoint: 0,
            reservedAmount: 0,
            nftTokenIds: nftTokenIds,
            tokenIdBalances: nftTokenIdBalances,
            nftCount: nftCount,
            holder: stakeholder,
            claimedAmount: oldStakeInfo.claimedAmount,
            gpuCount: gpuCount
        });

        _joinStaking(machineId, calcPoint, 0);
        _tryInitMachineLockRewardInfo(machineId, currentTime);

        holder2MachineIds[stakeholder].push(machineId);
        dbcAIContract.reportStakingStatus(projectName, StakingType.ShortTerm, machineId, 1, true);
        emit Staked(stakeholder, machineId, originCalcPoint, calcPoint);
        emit StakedGPUType(machineId, gpuType);
    }

    /**
     * @dev Gets comprehensive reward information for a staked machine
     * @param machineId The unique identifier of the machine
     * @return newRewardAmount The total new rewards accumulated for the machine
     * @return canClaimAmount The amount of rewards that can be claimed immediately
     * @return lockedAmount The amount of rewards that are locked
     * @return claimedAmount The amount of rewards already claimed
     */
    function getRewardInfo(string memory machineId)
        public
        view
        returns (uint256 newRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 totalRewardAmount = calculateRewards(machineId);
        (uint256 _canClaimAmount, uint256 _lockedAmount) = _getRewardDetail(totalRewardAmount);
        (uint256 releaseAmount, uint256 lockedAmountBefore) = calculateReleaseReward(machineId);

        return (
            totalRewardAmount,
            _canClaimAmount + releaseAmount,
            _lockedAmount + lockedAmountBefore,
            stakeInfo.claimedAmount
        );
    }

    /**
     * @dev Calculates the total number of NFTs from balance array
     * @param nftTokenIdBalances Array of NFT token balances
     * @return nftCount The total count of NFTs
     */
    function getNFTCount(uint256[] memory nftTokenIdBalances) internal pure returns (uint256 nftCount) {
        for (uint256 i = 0; i < nftTokenIdBalances.length; i++) {
            nftCount += nftTokenIdBalances[i];
        }

        return nftCount;
    }

    function _claim(string memory machineId) internal {
        if (!rewardStart()) {
            return;
        }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);
        _updateMachineRewards(machineId, machineShares);

        address stakeholder = stakeInfo.holder;
        uint256 currentTimestamp = block.timestamp;

        bool _isStaking = isStaking(machineId);
        uint256 rewardAmount = calculateRewards(machineId);

        machineId2StakeUnitRewards[machineId].accumulated = 0;

        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);

        (uint256 _dailyReleaseAmount,) = calculateReleaseRewardAndUpdate(machineId);
        canClaimAmount += _dailyReleaseAmount;

        uint256 moveToReserveAmount = 0;
        if (canClaimAmount > 0 && _isStaking) {
            if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
                (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                    tryMoveReserve(machineId, canClaimAmount, stakeInfo);
                canClaimAmount = leftAmountCanClaim;
                moveToReserveAmount = _moveToReserveAmount;
            }
        }

        if (canClaimAmount > 0) {
            require(rewardToken.balanceOf(address(this)) - totalReservedAmount >= canClaimAmount, RewardNotEnough());
            SafeERC20.safeTransfer(rewardToken, stakeholder, canClaimAmount);
        }

        uint256 totalRewardAmount = canClaimAmount + moveToReserveAmount;
        totalDistributedRewardAmount += totalRewardAmount;
        stakeInfo.claimedAmount += totalRewardAmount;
        stakeInfo.lastClaimAtTimestamp = currentTimestamp;

        if (lockedAmount > 0) {
            machineId2LockedRewardDetail[machineId].totalAmount += lockedAmount;
        }

        emit Claimed(stakeholder, machineId, lockedAmount, canClaimAmount, moveToReserveAmount);
    }

    /**
     * @dev Gets all machine IDs staked by a specific stakeholder
     * @param holder The address of the stakeholder
     * @return string[] Array of machine IDs owned by the stakeholder
     */
    function getMachineIdsByStakeholder(address holder) external view returns (string[] memory) {
        return holder2MachineIds[holder];
    }

    /**
     * @dev Gets aggregated reward information for all machines owned by a stakeholder
     * @param holder The address of the stakeholder
     * @return availableRewardAmount Total available rewards across all machines
     * @return canClaimAmount Total amount that can be claimed immediately
     * @return lockedAmount Total amount of locked rewards
     * @return claimedAmount Total amount already claimed
     */
    function getAllRewardInfo(address holder)
        external
        view
        returns (uint256 availableRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        string[] memory machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            (uint256 _availableRewardAmount, uint256 _canClaimAmount, uint256 _lockedAmount, uint256 _claimedAmount) =
                getRewardInfo(machineIds[i]);
            availableRewardAmount += _availableRewardAmount;
            canClaimAmount += _canClaimAmount;
            lockedAmount += _lockedAmount;
            claimedAmount += _claimedAmount;
        }
        return (availableRewardAmount, canClaimAmount, lockedAmount, claimedAmount);
    }

    /**
     * @dev Claims accumulated rewards for a staked machine
     * @param machineId The unique identifier of the machine to claim rewards for
     */
    function claim(string memory machineId) public {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        require(stakeInfo.holder == stakeholder, NotStakeHolder(machineId, stakeholder));

        _claim(machineId);
    }

    function tryMoveReserve(string memory machineId, uint256 canClaimAmount, StakeInfo storage stakeInfo)
        internal
        returns (uint256 moveToReserveAmount, uint256 leftAmountCanClaim)
    {
        uint256 leftAmountShouldReserve = BASE_RESERVE_AMOUNT - stakeInfo.reservedAmount;
        if (canClaimAmount >= leftAmountShouldReserve) {
            canClaimAmount -= leftAmountShouldReserve;
            moveToReserveAmount = leftAmountShouldReserve;
        } else {
            moveToReserveAmount = canClaimAmount;
            canClaimAmount = 0;
        }

        // the amount should be transfer to reserve
        totalReservedAmount += moveToReserveAmount;
        stakeInfo.reservedAmount += moveToReserveAmount;
        if (moveToReserveAmount > 0) {
            emit MoveToReserveAmount(machineId, stakeInfo.holder, moveToReserveAmount);
        }
        return (moveToReserveAmount, canClaimAmount);
    }

    function calculateReleaseRewardAndUpdate(string memory machineId)
        internal
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            lockedRewardDetail.claimedAmount = lockedRewardDetail.totalAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        lockedRewardDetail.claimedAmount += releaseAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    /**
     * @dev Calculates the amount of locked rewards that can be released
     * @param machineId The unique identifier of the machine
     * @return releaseAmount The amount of rewards that can be released now
     * @return lockedAmount The amount of rewards still locked
     */
    function calculateReleaseReward(string memory machineId)
        public
        view
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    /**
     * @dev Unstakes a machine and claims any pending rewards
     * @param machineId The unique identifier of the machine to unstake
     */
    function unStake(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if (msg.sender != address(this)) {
            require(stakeInfo.startAtTimestamp > 0, MachineNotStaked(machineId));
            (, bool isRegistered) = dbcAIContract.getMachineState(machineId, projectName, STAKING_TYPE);
            require(!isRegistered, MachineStillRegistered());
        } else {
            emit ExitStakingForOffline(machineId, stakeInfo.holder);
        }
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function forceUnStake(string calldata machineId) external onlyOwner {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function unStakeByHolder(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(msg.sender == stakeInfo.holder, NotStakeHolder(machineId, msg.sender));
        require(stakeInfo.startAtTimestamp > 0, MachineNotStaked(machineId));
        (, bool isRegistered) = dbcAIContract.getMachineState(machineId, projectName, STAKING_TYPE);
        require(!isRegistered, MachineStillRegistered());

        //        require(machineId2Rented[machineId] == false, InRenting());
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function _unStake(string calldata machineId, address stakeholder) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 reservedAmount = stakeInfo.reservedAmount;

        if (reservedAmount > 0) {
            SafeERC20.safeTransfer(rewardToken, stakeholder, reservedAmount);
            stakeInfo.reservedAmount = 0;
            totalReservedAmount = totalReservedAmount > reservedAmount ? totalReservedAmount - reservedAmount : 0;
        }

        nftToken.safeBatchTransferFrom(
            address(this), stakeholder, stakeInfo.nftTokenIds, stakeInfo.tokenIdBalances, "transfer"
        );
        stakeInfo.nftTokenIds = new uint256[](0);
        stakeInfo.tokenIdBalances = new uint256[](0);
        stakeInfo.nftCount = 0;
        _joinStaking(machineId, 0, 0);
        removeStakingMachineFromHolder(stakeholder, machineId);
        if (totalStakingGpuCount > 0) {
            totalStakingGpuCount -= 1;
        }

        dbcAIContract.reportStakingStatus(projectName, StakingType.ShortTerm, machineId, 1, false);
        emit Unstaked(stakeholder, machineId, reservedAmount);
    }

    function removeStakingMachineFromHolder(address holder, string memory machineId) internal {
        string[] storage machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
                machineIds[i] = machineIds[machineIds.length - 1];
                machineIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Gets the stakeholder address for a specific machine
     * @param machineId The unique identifier of the machine
     * @return address The address of the stakeholder who owns the machine
     */
    function getStakeHolder(string calldata machineId) external view returns (address) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder;
    }

    /**
     * @dev Checks if a machine is currently staking
     * @param machineId The unique identifier of the machine
     * @return bool True if the machine is actively staking, false otherwise
     */
    function isStaking(string memory machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        bool _isStaking = stakeInfo.holder != address(0) && stakeInfo.nftCount > 0;
        return _isStaking;
    }

    function reportMachineFault(string calldata machineId) internal {
        if (!rewardStart()) {
            return;
        }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        emit ReportMachineFault(machineId, slashToAddress);
        _claim(machineId);
        payForSlashing(machineId, stakeInfo, slashToAddress, true);
        _unStake(machineId, stakeInfo.holder);
    }

    function isStakingButOffline(string calldata machineId) internal view returns (bool) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.calcPoint == 0 && stakeInfo.nftCount > 0;
    }

    /**
     * @dev Gets the calculation points for a specific machine
     * @param machineId The unique identifier of the machine
     * @return uint256 The calculation points assigned to the machine
     */
    function getaCalcPoint(string memory machineId) external view returns (uint256) {
        StakeInfo memory info = machineId2StakeInfos[machineId];
        return info.calcPoint;
    }

    /**
     * @dev Gets comprehensive information about a staked machine
     * @param machineId The unique identifier of the machine
     * @return holder The address of the stakeholder
     * @return calcPoint The calculation points of the machine
     * @return startAtTimestamp When the staking started
     * @return reservedAmount The amount of tokens reserved
     * @return isOnline Whether the machine is online
     * @return isRegistered Whether the machine is registered
     */
    function getMachineInfo(string memory machineId)
        external
        view
        returns (
            address holder,
            uint256 calcPoint,
            uint256 startAtTimestamp,
            uint256 reservedAmount,
            bool isOnline,
            bool isRegistered
        )
    {
        StakeInfo memory info = machineId2StakeInfos[machineId];
        (bool _isOnline, bool _isRegistered) = dbcAIContract.getMachineState(machineId, projectName, STAKING_TYPE);
        return (info.holder, info.calcPoint, info.startAtTimestamp, info.reservedAmount, _isOnline, _isRegistered);
    }

    function payForSlashing(string memory machineId, StakeInfo storage stakeInfo, address slashTo, bool alreadyStaked)
        internal
    {
        uint256 slashAmount = stakeInfo.reservedAmount >= SLASH_AMOUNT ? SLASH_AMOUNT : stakeInfo.reservedAmount;
        SafeERC20.safeTransfer(rewardToken, slashTo, slashAmount);
        if (alreadyStaked) {
            _joinStaking(machineId, stakeInfo.calcPoint, stakeInfo.reservedAmount - SLASH_AMOUNT);
        }

        emit PaySlash(machineId, SLASH_AMOUNT);
    }

    function _getRewardDetail(uint256 totalRewardAmount)
        internal
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    /**
     * @dev Gets the total accumulated rewards for a machine
     * @param machineId The unique identifier of the machine
     * @return uint256 The total reward amount accumulated
     */
    function getReward(string memory machineId) external view returns (uint256) {
        return calculateRewards(machineId);
    }

    /**
     * @dev Checks if reward distribution has started
     * @return bool True if rewards are being distributed, false otherwise
     */
    function rewardStart() internal view returns (bool) {
        return rewardStartAtTimestamp > 0 && block.timestamp >= rewardStartAtTimestamp;
    }

    function _updateRewardPerCalcPoint() internal {
        uint256 accumulatedPerShareBefore = rewardsPerCalcPoint.accumulatedPerShare;
        rewardsPerCalcPoint = _getUpdatedRewardPerCalcPoint();
        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    }

    function _getUpdatedRewardPerCalcPoint() internal view returns (RewardCalculatorLib.RewardsPerShare memory) {
        uint256 rewardsPerSeconds = dailyRewardAmount / 1 days;
        if (rewardStartAtTimestamp == 0) {
            return RewardCalculatorLib.RewardsPerShare(0, 0);
        }

        RewardCalculatorLib.RewardsPerShare memory rewardsPerTokenUpdated = RewardCalculatorLib.getUpdateRewardsPerShare(
            rewardsPerCalcPoint, totalAdjustUnit, rewardsPerSeconds, rewardStartAtTimestamp
        );
        return rewardsPerTokenUpdated;
    }

    function _updateMachineRewards(string memory machineId, uint256 machineShares) internal {
        _updateRewardPerCalcPoint();

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];
        if (machineRewards.lastAccumulatedPerShare == 0) {
            machineRewards.lastAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;
        }
        RewardCalculatorLib.UserRewards memory machineRewardsUpdated =
            RewardCalculatorLib.getUpdateUserRewards(machineRewards, machineShares, rewardsPerCalcPoint);
        machineId2StakeUnitRewards[machineId] = machineRewardsUpdated;
    }

    /**
     * @dev Calculates the machine shares based on calculation points and reserved amount
     * @param calcPoint The calculation points of the machine
     * @param reservedAmount The amount of tokens reserved for the machine
     * @return uint256 The calculated machine shares
     */
    function _getMachineShares(uint256 calcPoint, uint256 reservedAmount) public pure returns (uint256) {
        return
            calcPoint * ToolLib.LnUint256(reservedAmount > BASE_RESERVE_AMOUNT ? reservedAmount : BASE_RESERVE_AMOUNT);
    }

    function _joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 oldLnReserved = ToolLib.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 machineShares = stakeInfo.calcPoint * oldLnReserved;

        uint256 newLnReserved =
            ToolLib.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);

        totalAdjustUnit -= stakeInfo.calcPoint * oldLnReserved;
        totalAdjustUnit += calcPoint * newLnReserved;

        // update machine rewards
        _updateMachineRewards(machineId, machineShares);

        totalCalcPoint = totalCalcPoint - stakeInfo.calcPoint + calcPoint;

        stakeInfo.calcPoint = calcPoint;
        if (reserveAmount > stakeInfo.reservedAmount) {
            SafeERC20.safeTransferFrom(
                rewardToken, stakeInfo.holder, address(this), reserveAmount - stakeInfo.reservedAmount
            );
        }
        if (reserveAmount != stakeInfo.reservedAmount) {
            totalReservedAmount = totalReservedAmount + reserveAmount - stakeInfo.reservedAmount;
            stakeInfo.reservedAmount = reserveAmount;
        }
    }

    /**
     * @dev Calculates the total rewards accumulated for a specific machine
     * @param machineId The unique identifier of the machine
     * @return uint256 The total reward amount calculated for the machine
     */
    function calculateRewards(string memory machineId) public view returns (uint256) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];

        RewardCalculatorLib.RewardsPerShare memory currentRewardPerCalcPoint = _getUpdatedRewardPerCalcPoint();
        uint256 v = machineRewards.lastAccumulatedPerShare;
        if (machineRewards.lastAccumulatedPerShare == 0) {
            v = rewardsPerCalcPoint.accumulatedPerShare;
        }
        uint256 rewardAmount = RewardCalculatorLib.calculatePendingUserRewards(
            machineShares, v, currentRewardPerCalcPoint.accumulatedPerShare
        );

        return machineRewards.accumulated + rewardAmount;
    }

    /**
     * @dev Returns the version number of the contract
     * @return uint256 The current version number
     */
    function version() external pure returns (uint256) {
        return 1;
    }

    function oneDayAccumulatedPerShare(uint256 currentAccumulatedPerShare, uint256 totalShares)
        internal
        view
        returns (uint256)
    {
        uint256 elapsed = 1 days;
        uint256 rewardsRate = dailyRewardAmount / 1 days;

        uint256 accumulatedPerShare = currentAccumulatedPerShare + 1 ether * elapsed * rewardsRate / totalShares;

        return accumulatedPerShare;
    }

    /**
     * @dev Pre-calculates potential rewards for a machine configuration
     * @param calcPoint The base calculation points of the machine
     * @param nftCount The number of NFTs to be staked
     * @param reserveAmount The amount of tokens to be reserved
     * @return uint256 The estimated daily reward amount
     */
    function preCalculateRewards(uint256 calcPoint, uint256 nftCount, uint256 reserveAmount)
        public
        view
        returns (uint256)
    {
        calcPoint = calcPoint * nftCount;
        uint256 machineShares = _getMachineShares(calcPoint, reserveAmount);
        uint256 machineAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;

        uint256 totalShares = totalAdjustUnit + machineShares;

        uint256 _oneDayAccumulatedPerShare = oneDayAccumulatedPerShare(machineAccumulatedPerShare, totalShares);

        uint256 rewardAmount = RewardCalculatorLib.calculatePendingUserRewards(
            machineShares, machineAccumulatedPerShare, _oneDayAccumulatedPerShare
        );

        return rewardAmount;
    }

    /**
     * @dev Updates and emits events for machine registration status changes
     * @param machineId The unique identifier of the machine
     * @param _registered True if machine is being registered, false if unregistered
     * @notice Internal function to handle registration status updates
     */
    function updateMachineRegisterStatus(string memory machineId, bool _registered) internal {
        if (_registered) {
            emit MachineRegistered(machineId);
        } else {
            emit MachineUnregistered(machineId);
        }
    }

     /**
     * @dev Handles notifications from the DBC AI contract about machine status changes
     * @param tp The type of notification
     * @param machineId The unique identifier of the machine
     * @return bool True if the notification was processed successfully
     */
    function notify(NotifyType tp, string calldata machineId) external onlyDBCAIContract returns (bool) {
        if (tp == NotifyType.ContractRegister) {
            registered = true;
            return true;
        }

        bool _isStaking = isStaking(machineId);
        if (!_isStaking) {
            return false;
        }

        bool machineInWorking = inWorkingMachine[machineId];

        if (tp == NotifyType.MachineOffline) {
            if (machineInWorking) {
              reportMachineFault(machineId);
            } else {
              stopRewarding(machineId);
            }
        } else if (tp == NotifyType.MachineOnline && isStakingButOffline(machineId)) {
            recoverRewarding(machineId);
        }else if (tp == NotifyType.MachineUnregister) {
            updateMachineRegisterStatus(machineId,false);
        }else if (tp == NotifyType.MachineRegister) {
            updateMachineRegisterStatus(machineId,true);
        }
        return true;
    }
    

    /**
     * @dev Stops reward distribution for a machine that went offline
     * @param machineId The unique identifier of the machine
     * @notice Sets calculation points to 0 while maintaining reserved amount
     */
    function stopRewarding(string memory machineId) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        _joinStaking(machineId, 0, stakeInfo.reservedAmount);
        emit ExitStakingForOffline(machineId, stakeInfo.holder);
    }

    /**
     * @dev Recovers reward distribution for a machine that came back online
     * @param machineId The unique identifier of the machine
     * @notice Restores calculation points and resumes reward distribution
     */
    function recoverRewarding(string memory machineId) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.calcPoint != 0) {
            return;
        }

        (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
        calcPoint = calcPoint * stakeInfo.nftCount;
        _joinStaking(machineId, calcPoint, stakeInfo.reservedAmount);
        emit RecoverRewarding(machineId, stakeInfo.holder);
    }

    /**
     * @dev Sets the working status of a machine
     * @param machineId The unique identifier of the machine
     * @param isWorking True if machine is working, false otherwise
     * @notice Only valid wallet addresses can call this function
     */
    function setMachineWorking(string calldata machineId, bool isWorking) external onlyValidWallet {
        inWorkingMachine[machineId] = isWorking;
        emit SetMachineWorking(machineId, isWorking);
    }

}
