// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStaking} from "../contracts/NFTStaking.sol";
import {IDBCAIContract} from "../contracts/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ToolLib} from "../contracts/library/ToolLib.sol";




// Mock ERC1155 contract for testing
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://example.com/api/token/{id}.json") {}

    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public {
        _mintBatch(to, ids, amounts, data);
    }
}


contract StakingTest is Test {
    NFTStaking public nftStaking;
    IERC20 public rewardToken;
    IERC1155 public nftToken;
    IDBCAIContract public dbcAIContract;
    //    ToolLib public tool;
    address owner = address(0x01);
    address admin2 = address(0x02);
    address admin3 = address(0x03);
    address admin4 = address(0x04);
    address admin5 = address(0x05);

    address stakeHolder2 = address(0x06);

    function setUp() public {
        vm.startPrank(owner);
        // Initialize mock ERC20 token
        MockERC20 mockRewardToken = new MockERC20();
        mockRewardToken.initialize("Reward Token", "RWT", 18);
        rewardToken = IERC20(address(mockRewardToken));
        
        // Initialize mock ERC1155 token
        MockERC1155 mockNFTToken = new MockERC1155();
        nftToken = IERC1155(address(mockNFTToken));

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        NFTStaking(address(proxy1)).initialize(
            owner, address(nftToken), address(rewardToken), address(dbcAIContract), address(0x00),"testProjectName"
        );

        deal(address(rewardToken), address(this), 100000000000 * 1e18);
        deal(address(rewardToken), owner, 180000000 * 1e18);
        rewardToken.approve(address(nftStaking), 180000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 50000000000 * 1e18);

        passHours(1);
        address[] memory addrs = new address[](1);
        addrs[0] = owner;
        nftStaking.setDLCClientWallets(addrs);
        vm.mockCall(
            address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode()
        );
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.stopPrank();
    }

    

    function stakeByOwner(
        string memory machineId,
        uint256 reserveAmount,
        address _owner,
        uint256 nftTokenId,
        uint256 nftTokenCount
    ) public {


        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(_owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );


        vm.startPrank(_owner);
        dealERC1155(address(nftToken), _owner, nftTokenId, nftTokenCount, false);

        assertEq(nftToken.balanceOf(_owner, nftTokenId), nftTokenCount, "owner erc1155 failed");
        deal(address(rewardToken), _owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        vm.startPrank(owner);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](nftTokenCount);
        nftTokens[0] = nftTokenId;
        for (uint256 i = 0; i < nftTokens.length; i++) {
            nftTokensBalance[i] = nftTokenCount;
        }
        uint256 totalCalcPointBefore = nftStaking.totalCalcPoint();
        nftStaking.stake(_owner, machineId, nftTokens, nftTokensBalance);
        assertEq(nftToken.balanceOf(_owner, nftTokenId), 0, "owner erc1155 failed");
        nftStaking.addTokenToStake(machineId, reserveAmount);
        vm.stopPrank();
        uint256 totalCalcPoint = nftStaking.totalCalcPoint();

        assertEq(totalCalcPoint, totalCalcPointBefore + 100);
        (uint256 accumulatedPerShare,) = nftStaking.rewardsPerCalcPoint();
        (uint256 accumulated, uint256 lastAccumulatedPerShare) = nftStaking.machineId2StakeUnitRewards(machineId);
        assertEq(accumulatedPerShare, lastAccumulatedPerShare);
        assertEq(accumulated, 0);

    }

    function testStake() public {
        address stakeHolder = owner;
       
        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";

        vm.startPrank(stakeHolder);
        stakeByOwner(machineId, 0, stakeHolder, 1, 1);
        vm.stopPrank();
        passDays(1);

        vm.startPrank(stakeHolder);
        assertLt(
            nftStaking.getReward(machineId),
            nftStaking.dailyRewardAmount(),
            "get reward lt failed after reward start 1 day 1"
        );
        assertGt(
            nftStaking.getReward(machineId),
            nftStaking.dailyRewardAmount() - 1 * 1e18,
            "get reward gt failed after reward start 1 day 2"
        );
        vm.stopPrank();

        vm.prank(stakeHolder2);
        stakeByOwner(machineId2, 0, stakeHolder2,1,1);
        passDays(1);


        uint256 reward2 = nftStaking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");

        assertLt(
            reward2,
            nftStaking.dailyRewardAmount() / 2,
            "machineId2 get reward lt staking.getDailyRewardAmount()/2 failed after staked 1 day"
        );

        assertGt(
            nftStaking.getReward(machineId2),
            nftStaking.dailyRewardAmount() / 2 - 1 * 1e18,
            "machineId2 get reward gt staking.getDailyRewardAmount()/2 - 1 * 1e18 failed after staked 1 day"
        );

        (, uint256 rewardAmountCanClaim, uint256 lockedRewardAmount,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim, reward2 / 10);
        assertEq(lockedRewardAmount, reward2 - reward2 / 10);

        passDays(1);
        uint256 reward4 = nftStaking.getReward(machineId2);

        (, uint256 rewardAmountCanClaim0, uint256 lockedRewardAmount0,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim0, reward4 / 10);
        assertEq(lockedRewardAmount0, reward4 - reward4 / 10);

        vm.prank(stakeHolder2);
        nftStaking.claim(machineId2);

        reward4 = nftStaking.getReward(machineId2);
        assertEq(reward4, 0, "machineId2 get reward  failed after claim");

        passDays(1);
        (uint256 release, uint256 locked) = nftStaking.calculateReleaseReward(machineId2);
        assertEq(release, ((locked + release) * 3 days / nftStaking.LOCK_PERIOD()), "111");
        vm.stopPrank();
        console.log("release", release);
        console.log("locked", release);

    }

    function testUnStake() public {
        address stakeHolder = owner;
        string memory machineId = "machineId";
        stakeByOwner(machineId, 100000, stakeHolder,1,1);

        passHours(48);
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, false)
        );

        vm.startPrank(stakeHolder);
        nftStaking.unStake(machineId);
        vm.stopPrank();
        assertEq(nftToken.balanceOf(stakeHolder, 1), 1, "owner erc1155 failed");

        nftStaking.getRewardInfo(machineId);
        uint256 balance1 = rewardToken.balanceOf(stakeHolder);

        passHours(24);
        vm.startPrank(stakeHolder);
        nftStaking.claim(machineId);
        vm.stopPrank();
        uint256 balance2 = rewardToken.balanceOf(stakeHolder);

        assertGt(balance2, balance1, "claim failed");
    }

    function testUnStakeByHolderAndReStake() public {
        // Test if a miner can claim rewards from previous staking period after unstaking early and staking again
        address stakeHolder = owner;
        string memory machineId = "machineId";

        // First staking period
        stakeByOwner(machineId, 100000, stakeHolder,1,1);

        // Pass some time to accumulate rewards but not the full staking period
        passHours(24);

        // Check rewards accumulated
        uint256 rewardBefore = nftStaking.getReward(machineId);
        assertGt(rewardBefore, 0, "Should have accumulated some rewards");

        // Mock machine is not registered to allow unstaking
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, false)
        );

        // Unstake early using unStakeByHolder
        vm.startPrank(stakeHolder);
        nftStaking.unStakeByHolder(machineId);
        vm.stopPrank();

        // Verify NFT returned to holder
        assertEq(nftToken.balanceOf(stakeHolder, 1), 1, "NFT should be returned to owner");

        // Pass some time
        passHours(12);

        // Re-stake the same machine
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        stakeByOwner(machineId, 100000, stakeHolder,1,1);

        // Pass more time
        passHours(24);

        // Check if rewards can be claimed
        uint256 balanceBefore = rewardToken.balanceOf(stakeHolder);

        vm.startPrank(stakeHolder);
        nftStaking.claim(machineId);
        vm.stopPrank();

        uint256 balanceAfter = rewardToken.balanceOf(stakeHolder);

        // Verify rewards were claimed
        assertGt(balanceAfter, balanceBefore, "Should be able to claim rewards after re-staking");

        // Verify that rewards from the new staking period are separate from previous period
        (,,, uint256 claimedAmount) = nftStaking.getRewardInfo(machineId);
        assertGt(claimedAmount, 0, "Should have claimed some rewards");
    }

    function testTool() public pure {
        string memory gpuType1 = "NVIDIA GeForce RTX 4060 Ti";
        assertEq(ToolLib.checkString(gpuType1), true, "checkString failed1");

        string memory gpuType2 = "Gen Intel(R) Core(TM) i7-13790F";
        assertEq(ToolLib.checkString(gpuType2), false, "checkString failed2");

        string memory gpuType3 = "NVIDIA GeForce RTX 20 Ti";
        assertEq(ToolLib.checkString(gpuType3), true, "checkString failed3");
    }

    function claimAfter(string memory machineId, address _owner, uint256 hour, bool shouldGetMore) internal {
        uint256 balance1 = rewardToken.balanceOf(_owner);
        passHours(hour);
        vm.prank(_owner);
        nftStaking.claim(machineId);
        uint256 balance2 = rewardToken.balanceOf(_owner);
        if (shouldGetMore) {
            assertGt(balance2, balance1);
        } else {
            assertEq(balance2, balance1);
        }
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passDays(uint256 n) public {
        uint256 secondsToAdvance = n * 24 * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passBlocks(uint256 n) public {
        uint256 timeToAdvance = n * nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + timeToAdvance - 1);
        vm.roll(vm.getBlockNumber() + n - 1);
    }

    function testLockedRewardFullClaimAfterLockPeriod() public {
        console.log("contract reweard balance", rewardToken.balanceOf(address(nftStaking)) / 1e18);

        // Test if a user can claim all locked rewards after the lock period ends
        address stakeHolder = owner;
        string memory machineId = "machineId";

        // Setup staking
        stakeByOwner(machineId, 100000 ether, stakeHolder,1,1);

      
        // Pass some time to accumulate rewards
        passHours(24);

        // Check initial rewards
        (uint256 totalReward, uint256 canClaimNow, uint256 lockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(totalReward, 0, "Should have accumulated some rewards");
        assertGt(lockedAmount, 0, "Should have some locked rewards");
        console.log("totalReward", totalReward / 1e18);
        console.log("canClaimNow", canClaimNow / 1e18);
        console.log("lockedAmount", lockedAmount / 1e18);
        // Claim rewards first time - this will lock 90% of rewards
        vm.startPrank(stakeHolder);
        uint256 balanceBefore = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfter = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();

        // Verify immediate claim (10% of rewards) - 
        assertEq(balanceAfter - balanceBefore, canClaimNow, "Should have claimed immediate rewards");

        // Get locked reward details
        (,, uint256 stillLockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(stillLockedAmount, 0, "Should still have locked rewards");

        // Fast forward to after lock period (180 days)
        vm.warp(block.timestamp + nftStaking.LOCK_PERIOD() + 1);

        // uint256 leftLocked = total-claimed;

        // Check rewards after lock period
        (, uint256 newCanClaimNow, uint256 newLockedAmount,) = nftStaking.getRewardInfo(machineId);

        // All previously locked rewards should now be claimable
        assertGt(newLockedAmount, 0, "Should have new locked rewards after lock period");
        assertGt(newCanClaimNow, 0, "Should have claimable rewards after lock period");

        // Claim all rewards after lock period
        vm.startPrank(stakeHolder);
        uint256 balanceBeforeFinal = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfterFinal = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();

        assertApproxEqRel(
            balanceAfterFinal - balanceBeforeFinal, newCanClaimNow, 0.01e18, "Should have claimed all unlocked rewards"
        );

        // Verify no more locked rewards
        (, uint256 finalCanClaimNow, uint256 finalLockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(finalCanClaimNow, 0, "Should have new rewards after claiming");
        assertEq(finalLockedAmount, 0, "Should have no locked rewards after claiming");

        (uint256 total, uint256 startTime, uint256 endTime, uint256 claimed) =
            nftStaking.machineId2LockedRewardDetail(machineId);
        assertEq(endTime - startTime, nftStaking.LOCK_PERIOD());
        uint256 left = total - claimed;
        vm.startPrank(stakeHolder);
        uint256 balanceBeforeFinal1 = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfterFinal1 = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();
        assertEq(left, balanceAfterFinal1 - balanceBeforeFinal1);

        (uint256 totalFinal,,, uint256 claimedFinal) = nftStaking.machineId2LockedRewardDetail(machineId);

        assertEq(totalFinal, claimedFinal);
    }
}
