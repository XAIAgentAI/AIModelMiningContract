# NFTStaking 合约接口文档

## 概述

NFTStaking 是一个基于 ERC1155 NFT 的质押合约，允许用户质押 NFT 来获得代币奖励。合约支持机器状态管理、奖励计算、锁定期管理等功能。

## 合约信息

- **合约名称**: NFTStaking
- **Solidity 版本**: 0.8.26
- **继承**: Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable, IERC1155Receiver
- **升级模式**: UUPS 可升级代理模式

## 常量

| 常量名 | 类型 | 值 | 描述 |
|--------|------|----|---------|
| `SECONDS_PER_BLOCK` | uint8 | 6 | 每个区块的秒数 |
| `BASE_RESERVE_AMOUNT` | uint256 | 100,000 ether | 基础保证金数量 |
| `MAX_NFTS_PER_MACHINE` | uint8 | 10 | 每台机器最大 NFT 数量 |
| `LOCK_PERIOD` | uint256 | 180 days | 奖励锁定期 |
| `SLASH_AMOUNT` | uint256 | 100,000 ether | 惩罚金额 |

## 状态变量

### 核心合约引用
- `IDBCAIContract public dbcAIContract` - DBC AI 合约接口
- `IERC1155 public nftToken` - NFT 代币合约
- `IERC20 public rewardToken` - 奖励代币合约

### 管理变量
- `address public canUpgradeAddress` - 可升级地址
- `address public slashToAddress` - 惩罚接收地址
- `string public projectName` - 项目名称
- `bool public registered` - 注册状态

### 奖励相关
- `uint256 public totalDistributedRewardAmount` - 总分发奖励数量
- `uint256 public rewardStartAtTimestamp` - 奖励开始时间戳
- `uint256 public dailyRewardAmount` - 每日奖励数量
- `uint256 public totalAdjustUnit` - 总调整单位
- `RewardCalculatorLib.RewardsPerShare public rewardsPerCalcPoint` - 每计算点奖励

### 质押统计
- `uint256 public totalGpuCount` - 总 GPU 数量
- `uint256 public totalStakingGpuCount` - 总质押 GPU 数量
- `uint256 public totalReservedAmount` - 总保证金数量
- `uint256 public totalCalcPoint` - 总计算点数
- `string[] public stakedMachineIds` - 已质押机器 ID 列表

## 数据结构

### StakeInfo
```solidity
struct StakeInfo {
    address holder;              // 持有者地址
    uint256 startAtTimestamp;    // 开始时间戳
    uint256 lastClaimAtTimestamp; // 最后领取时间戳
    uint256 calcPoint;           // 计算点数
    uint256 reservedAmount;      // 保证金数量
    uint256[] nftTokenIds;       // NFT 代币 ID 数组
    uint256[] tokenIdBalances;   // 代币 ID 余额数组
    uint256 nftCount;            // NFT 数量
    uint256 claimedAmount;       // 已领取数量
    uint256 gpuCount;            // GPU 数量
}
```

### LockedRewardDetail
```solidity
struct LockedRewardDetail {
    uint256 totalAmount;    // 总锁定数量
    uint256 lockTime;       // 锁定时间
    uint256 unlockTime;     // 解锁时间
    uint256 claimedAmount;  // 已领取数量
}
```

## 主要功能函数

### 初始化函数

#### `initialize`
```solidity
function initialize(
    address _initialOwner,
    address _nftToken,
    address _rewardToken,
    address _dbcAIContract,
    address _slashToAddress,
    string memory _projectName
) public initializer
```
**描述**: 初始化合约
**参数**:
- `_initialOwner`: 初始所有者地址
- `_nftToken`: NFT 代币合约地址
- `_rewardToken`: 奖励代币合约地址
- `_dbcAIContract`: DBC AI 合约地址
- `_slashToAddress`: 惩罚接收地址
- `_projectName`: 项目名称

### 质押相关函数

#### `stake`
```solidity
function stake(
    address stakeholder,
    string calldata machineId,
    uint256[] calldata nftTokenIds,
    uint256[] calldata nftTokenIdBalances
) external onlyValidWallet canStake(stakeholder, machineId, nftTokenIds, nftTokenIdBalances) nonReentrant
```
**描述**: 质押 NFT 到指定机器
**参数**:
- `stakeholder`: 质押者地址
- `machineId`: 机器 ID
- `nftTokenIds`: NFT 代币 ID 数组
- `nftTokenIdBalances`: NFT 代币余额数组
**权限**: 仅有效钱包地址
**事件**: 触发 `Staked` 和 `StakedGPUType` 事件

#### `unStake`
```solidity
function unStake(string calldata machineId) public nonReentrant
```
**描述**: 解除质押
**参数**:
- `machineId`: 机器 ID
**事件**: 触发 `Unstaked` 事件

#### `unStakeByHolder`
```solidity
function unStakeByHolder(string calldata machineId) public nonReentrant
```
**描述**: 持有者主动解除质押
**参数**:
- `machineId`: 机器 ID
**权限**: 仅质押持有者

#### `forceUnStake`
```solidity
function forceUnStake(string calldata machineId) external onlyOwner
```
**描述**: 强制解除质押
**参数**:
- `machineId`: 机器 ID
**权限**: 仅合约所有者

### 奖励相关函数

#### `claim`
```solidity
function claim(string memory machineId) public
```
**描述**: 领取奖励
**参数**:
- `machineId`: 机器 ID
**权限**: 仅质押持有者
**事件**: 触发 `Claimed` 事件

#### `getRewardInfo`
```solidity
function getRewardInfo(string memory machineId)
    public view returns (
        uint256 newRewardAmount,
        uint256 canClaimAmount,
        uint256 lockedAmount,
        uint256 claimedAmount
    )
```
**描述**: 获取奖励信息
**参数**:
- `machineId`: 机器 ID
**返回值**:
- `newRewardAmount`: 新奖励数量
- `canClaimAmount`: 可领取数量
- `lockedAmount`: 锁定数量
- `claimedAmount`: 已领取数量

#### `getAllRewardInfo`
```solidity
function getAllRewardInfo(address holder)
    external view returns (
        uint256 availableRewardAmount,
        uint256 canClaimAmount,
        uint256 lockedAmount,
        uint256 claimedAmount
    )
```
**描述**: 获取持有者所有奖励信息
**参数**:
- `holder`: 持有者地址
**返回值**: 聚合的奖励信息

#### `calculateRewards`
```solidity
function calculateRewards(string memory machineId) public view returns (uint256)
```
**描述**: 计算奖励
**参数**:
- `machineId`: 机器 ID
**返回值**: 奖励数量

#### `preCalculateRewards`
```solidity
function preCalculateRewards(
    uint256 calcPoint,
    uint256 nftCount,
    uint256 reserveAmount
) public view returns (uint256)
```
**描述**: 预计算奖励
**参数**:
- `calcPoint`: 计算点数
- `nftCount`: NFT 数量
- `reserveAmount`: 保证金数量
**返回值**: 预计奖励数量

### 查询函数

#### `isStaking`
```solidity
function isStaking(string memory machineId) public view returns (bool)
```
**描述**: 检查机器是否在质押中
**参数**:
- `machineId`: 机器 ID
**返回值**: 是否在质押中

#### `getStakeHolder`
```solidity
function getStakeHolder(string calldata machineId) external view returns (address)
```
**描述**: 获取质押持有者
**参数**:
- `machineId`: 机器 ID
**返回值**: 持有者地址

#### `getMachineIdsByStakeholder`
```solidity
function getMachineIdsByStakeholder(address holder) external view returns (string[] memory)
```
**描述**: 获取持有者的机器 ID 列表
**参数**:
- `holder`: 持有者地址
**返回值**: 机器 ID 数组

#### `getMachineInfo`
```solidity
function getMachineInfo(string memory machineId)
    external view returns (
        address holder,
        uint256 calcPoint,
        uint256 startAtTimestamp,
        uint256 reservedAmount,
        bool isOnline,
        bool isRegistered
    )
```
**描述**: 获取机器信息
**参数**:
- `machineId`: 机器 ID
**返回值**: 机器的详细信息

#### `machineIsBlocked`
```solidity
function machineIsBlocked(string memory machineId) external view returns (bool)
```
**描述**: 检查机器是否被阻止
**参数**:
- `machineId`: 机器 ID
**返回值**: 是否被阻止

### 管理员函数

#### `setUpgradeAddress`
```solidity
function setUpgradeAddress(address addr) external onlyOwner
```
**描述**: 设置升级地址
**参数**:
- `addr`: 新的升级地址
**权限**: 仅合约所有者

#### `setRewardToken`
```solidity
function setRewardToken(address token) external onlyOwner
```
**描述**: 设置奖励代币
**参数**:
- `token`: 奖励代币地址
**权限**: 仅合约所有者

#### `setNftToken`
```solidity
function setNftToken(address token) external onlyOwner
```
**描述**: 设置 NFT 代币
**参数**:
- `token`: NFT 代币地址
**权限**: 仅合约所有者

#### `setRewardStartAt`
```solidity
function setRewardStartAt(uint256 timestamp) external onlyOwner
```
**描述**: 设置奖励开始时间
**参数**:
- `timestamp`: 开始时间戳
**权限**: 仅合约所有者

#### `setDLCClientWallets`
```solidity
function setDLCClientWallets(address[] calldata addrs) external onlyOwner
```
**描述**: 设置 DLC 客户端钱包地址
**参数**:
- `addrs`: 钱包地址数组
**权限**: 仅合约所有者

#### `setDBCAIContract`
```solidity
function setDBCAIContract(address addr) external onlyOwner
```
**描述**: 设置 DBC AI 合约地址
**参数**:
- `addr`: 合约地址
**权限**: 仅合约所有者

#### `setMachineWorking`
```solidity
function setMachineWorking(string calldata machineId, bool isWorking) external onlyValidWallet
```
**描述**: 设置机器工作状态
**参数**:
- `machineId`: 机器 ID
- `isWorking`: 是否工作中
**权限**: 仅有效钱包地址
**事件**: 触发 `SetMachineWorking` 事件

### 其他功能函数

#### `addTokenToStake`
```solidity
function addTokenToStake(string memory machineId, uint256 amount) external nonReentrant
```
**描述**: 向质押中添加代币
**参数**:
- `machineId`: 机器 ID
- `amount`: 添加数量
**事件**: 触发 `ReserveDLC` 事件

#### `notify`
```solidity
function notify(NotifyType tp, string calldata machineId) external onlyDBCAIContract returns (bool)
```
**描述**: 接收通知
**参数**:
- `tp`: 通知类型
- `machineId`: 机器 ID
**权限**: 仅 DBC AI 合约
**返回值**: 处理结果

#### `version`
```solidity
function version() external pure returns (uint256)
```
**描述**: 获取合约版本
**返回值**: 版本号

## 事件

### 质押相关事件

#### `Staked`
```solidity
event Staked(address indexed stakeholder, string machineId, uint256 originCalcPoint, uint256 calcPoint)
```
**描述**: 质押事件
**参数**:
- `stakeholder`: 质押者地址
- `machineId`: 机器 ID
- `originCalcPoint`: 原始计算点数
- `calcPoint`: 实际计算点数

#### `StakedGPUType`
```solidity
event StakedGPUType(string machineId, string gpuType)
```
**描述**: 质押 GPU 类型事件
**参数**:
- `machineId`: 机器 ID
- `gpuType`: GPU 类型

#### `Unstaked`
```solidity
event Unstaked(address indexed stakeholder, string machineId, uint256 paybackReserveAmount)
```
**描述**: 解除质押事件
**参数**:
- `stakeholder`: 质押者地址
- `machineId`: 机器 ID
- `paybackReserveAmount`: 退还保证金数量

### 奖励相关事件

#### `Claimed`
```solidity
event Claimed(
    address indexed stakeholder,
    string machineId,
    uint256 lockedRewardAmount,
    uint256 moveToUserWalletAmount,
    uint256 moveToReservedAmount
)
```
**描述**: 领取奖励事件
**参数**:
- `stakeholder`: 质押者地址
- `machineId`: 机器 ID
- `lockedRewardAmount`: 锁定奖励数量
- `moveToUserWalletAmount`: 转入用户钱包数量
- `moveToReservedAmount`: 转入保证金数量

#### `RewardsPerCalcPointUpdate`
```solidity
event RewardsPerCalcPointUpdate(uint256 accumulatedPerShareBefore, uint256 accumulatedPerShareAfter)
```
**描述**: 每计算点奖励更新事件
**参数**:
- `accumulatedPerShareBefore`: 更新前累积值
- `accumulatedPerShareAfter`: 更新后累积值

### 机器状态事件

#### `SetMachineWorking`
```solidity
event SetMachineWorking(string machineId, bool isWorking)
```
**描述**: 设置机器工作状态事件
**参数**:
- `machineId`: 机器 ID
- `isWorking`: 是否工作中

#### `MachineRegistered`
```solidity
event MachineRegistered(string machineId)
```
**描述**: 机器注册事件
**参数**:
- `machineId`: 机器 ID

#### `ExitStakingForOffline`
```solidity
event ExitStakingForOffline(string machineId, address holder)
```
**描述**: 因离线退出质押事件
**参数**:
- `machineId`: 机器 ID
- `holder`: 持有者地址

#### `RecoverRewarding`
```solidity
event RecoverRewarding(string machineId, address holder)
```
**描述**: 恢复奖励事件
**参数**:
- `machineId`: 机器 ID
- `holder`: 持有者地址

### 其他事件

#### `ReserveDLC`
```solidity
event ReserveDLC(string machineId, uint256 amount)
```
**描述**: 保证金事件
**参数**:
- `machineId`: 机器 ID
- `amount`: 数量

#### `PaySlash`
```solidity
event PaySlash(string machineId, uint256 slashAmount)
```
**描述**: 支付惩罚事件
**参数**:
- `machineId`: 机器 ID
- `slashAmount`: 惩罚数量

#### `ReportMachineFault`
```solidity
event ReportMachineFault(string machineId, address renter)
```
**描述**: 报告机器故障事件
**参数**:
- `machineId`: 机器 ID
- `renter`: 租用者地址

#### `MoveToReserveAmount`
```solidity
event MoveToReserveAmount(string machineId, address holder, uint256 amount)
```
**描述**: 转入保证金事件
**参数**:
- `machineId`: 机器 ID
- `holder`: 持有者地址
- `amount`: 数量

#### `RenewRent`
```solidity
event RenewRent(string machineId, address holder, uint256 rentFee)
```
**描述**: 续租事件
**参数**:
- `machineId`: 机器 ID
- `holder`: 持有者地址
- `rentFee`: 租金

## 错误定义

| 错误名 | 描述 |
|--------|------|
| `RewardNotStart()` | 奖励未开始 |
| `CallerNotRentContract()` | 调用者不是租赁合约 |
| `ZeroAddress()` | 零地址 |
| `AddressExists()` | 地址已存在 |
| `CanNotUpgrade(address)` | 无法升级 |
| `TimestampLessThanCurrent()` | 时间戳小于当前时间 |
| `MachineNotStaked(string machineId)` | 机器未质押 |
| `MachineIsStaking(string machineId)` | 机器正在质押中 |
| `MemorySizeLessThan16G(uint256 mem)` | 内存大小小于 16G |
| `GPUTypeNotMatch(string gpuType)` | GPU 类型不匹配 |
| `ZeroCalcPoint()` | 零计算点数 |
| `InvalidNFTLength(uint256 tokenIdLength, uint256 balanceLength)` | 无效的 NFT 长度 |
| `NotMachineOwner(address)` | 不是机器所有者 |
| `ZeroNFTTokenIds()` | 零 NFT 代币 ID |
| `NFTCountGreaterThan20()` | NFT 数量大于 20 |
| `NotPaidSlashBeforeClaim(string machineId, uint256 slashAmount)` | 领取前未支付惩罚 |
| `NotStakeHolder(string machineId, address currentAddress)` | 不是质押持有者 |
| `MachineRentedByUser()` | 机器被用户租用 |
| `MachineNotRented()` | 机器未被租用 |
| `NotAdmin()` | 不是管理员 |
| `MachineNotStakeEnoughDBC()` | 机器未质押足够的 DBC |
| `MachineNotOnlineOrRegistered()` | 机器未在线或未注册 |
| `NotMachineOwnerOrAdmin()` | 不是机器所有者或管理员 |
| `MachineStillRegistered()` | 机器仍然注册 |
| `StakingInLongTerm()` | 长期质押中 |
| `IsStaking()` | 正在质押中 |
| `RewardNotEnough()` | 奖励不足 |
| `TotalRateNotEq100()` | 总比率不等于 100 |
| `NotDBCAIContract()` | 不是 DBC AI 合约 |

## 修饰符

### `onlyValidWallet`
**描述**: 仅有效钱包地址可调用
**条件**: `validWalletAddress[msg.sender] || msg.sender == owner()`

### `onlyDBCAIContract`
**描述**: 仅 DBC AI 合约可调用
**条件**: `msg.sender == address(dbcAIContract)`

### `canStake`
**描述**: 可以质押的条件检查
**条件**: 
- 奖励已开始
- 调用者是有效钱包
- 机器未在质押中
- 机器有足够的 DBC
- NFT 数组长度有效
- 机器在线且已注册
- NFT ID 数组不为空

## 使用示例

### 质押 NFT
```solidity
// 1. 首先批准 NFT 转移
nftToken.setApprovalForAll(nftStakingAddress, true);

// 2. 准备质押参数
uint256[] memory tokenIds = [1, 2, 3];
uint256[] memory amounts = [1, 1, 1];

// 3. 执行质押
nftStaking.stake(stakeholder, "machine123", tokenIds, amounts);
```

### 领取奖励
```solidity
// 领取指定机器的奖励
nftStaking.claim("machine123");
```

### 查询奖励信息
```solidity
// 查询单个机器的奖励信息
(uint256 newReward, uint256 canClaim, uint256 locked, uint256 claimed) = 
    nftStaking.getRewardInfo("machine123");

// 查询持有者所有奖励信息
(uint256 totalAvailable, uint256 totalCanClaim, uint256 totalLocked, uint256 totalClaimed) = 
    nftStaking.getAllRewardInfo(holderAddress);
```

### 解除质押
```solidity
// 持有者主动解除质押
nftStaking.unStakeByHolder("machine123");
```

## 注意事项

1. **权限管理**: 大部分管理功能需要合约所有者权限，质押相关功能需要有效钱包地址权限
2. **重入保护**: 关键函数使用了 `nonReentrant` 修饰符防止重入攻击
3. **升级安全**: 合约使用 UUPS 模式，只有指定的升级地址才能执行升级
4. **奖励机制**: 奖励分为即时释放（10%）和线性释放（90%，锁定 180 天）
5. **机器状态**: 机器必须在线且已注册才能进行质押
6. **NFT 限制**: 每台机器最多可质押 10 个 NFT
7. **保证金机制**: 系统会自动管理保证金，确保有足够的资金用于惩罚

## 版本信息
- **部署状态**：未部署
- **当前版本**: 1
- **兼容性**: 支持从 OldNFTStaking 升级