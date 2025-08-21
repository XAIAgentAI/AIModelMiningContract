// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./DeployHelpers.s.sol";
import "../contracts/NFTStaking.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @notice Upgrade script for NFTStaking contract
 * @dev This script upgrades the implementation of an existing proxy
 * Example:
 * yarn deploy --file UpgradeNFTStaking.s.sol --network optimism
 */
contract UpgradeNFTStaking is ScaffoldETHDeploy {
    /**
     * @dev Upgrades the NFTStaking contract implementation
     * You need to set the proxy address before running this script
     */
    function run() external ScaffoldEthDeployerRunner {
        // Set the proxy address of the deployed contract
        address proxyAddress = address(0); // TODO: Set your proxy address here

        require(proxyAddress != address(0), "Proxy address not set");

        // Deploy new implementation
        NFTStaking newImplementation = new NFTStaking();

        // Get the NFTStaking proxy instance
        NFTStaking nftStaking = NFTStaking(proxyAddress);

        // Upgrade to new implementation
        nftStaking.upgradeToAndCall(
            address(newImplementation),
            "" // No additional initialization data needed
        );

        console.log("NFTStaking upgraded to new implementation:", address(newImplementation));
        console.log("Proxy address:", proxyAddress);
    }
}
