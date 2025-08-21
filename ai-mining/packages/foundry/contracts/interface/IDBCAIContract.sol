pragma solidity 0.8.26;

import { NFTStaking } from "../NFTStaking.sol";
import { StakingType } from "../types.sol";

interface IDBCAIContract {
    function getMachineState(string calldata machineId, string calldata projectName, StakingType stakingType)
        external
        view
        returns (bool isOnline, bool isRegistered);

    function getMachineInfo(string calldata id, bool isDeepLink)
        external
        view
        returns (
            address machineOwner,
            uint256 calcPoint,
            uint256 cpuRate,
            string memory gpuType,
            uint256 gpuMem,
            string memory cpuType,
            uint256 gpuCount,
            string memory machineId,
            uint256 memorySize
        );

    function freeGpuAmount(string calldata) external pure returns (uint256);

    function reportStakingStatus(
        string calldata projectName,
        StakingType stakingType,
        string calldata id,
        uint256 gpuNum,
        bool isStake
    ) external;
}
