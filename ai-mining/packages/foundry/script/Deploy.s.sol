// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "../contracts/NFTStaking.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import { console } from "forge-std/Test.sol";

contract Deploy is Script {
    function run() external returns (address proxy, address logic) {
        // string memory privateKeyString = vm.envString("PRIVATE_KEY");
        // uint256 deployerPrivateKey;

        // if (
        //     bytes(privateKeyString).length > 0 && bytes(privateKeyString)[0] == "0" && bytes(privateKeyString)[1] == "x"
        // ) {
        //     deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // } else {
        //     deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        // }

        vm.startBroadcast();

        (proxy, logic) = deploy();
        vm.stopBroadcast();
        console.log("Proxy Contract deployed at:", proxy);
        console.log("Logic Contract deployed at:", logic);
        return (proxy, logic);
    }

    function deploy() public returns (address proxy, address logic) {
        Options memory opts;
        (, address _deployer,) = vm.readCallers();

        address initialOwner = _deployer;
        logic = Upgrades.deployImplementation("NFTStaking.sol:NFTStaking", opts);
        console.log("NFTStaking Implementation deployed at:", logic);

        address nftContract = vm.envAddress("NFT_CONTRACT");
        console.log("nftContract Address:", nftContract);

        address rewardTokenContract = vm.envAddress("REWARD_TOKEN_CONTRACT");
        console.log("rewardTokenContract Address:", rewardTokenContract);

        address dbcAIProxy = vm.envAddress("DBC_AI_PROXY");
        console.log("DBC AI Proxy Address:", dbcAIProxy);

        address slashToAddress = vm.envAddress("SLASH_TO_ADDRESS");
        console.log("slashToAddress:", slashToAddress);

        string memory projectName = vm.envString("PROJECT_NAME");
        console.log("projectName:", projectName);

        proxy = Upgrades.deployUUPSProxy(
            "NFTStaking.sol:NFTStaking",
            abi.encodeCall(
                NFTStaking.initialize, (initialOwner, nftContract, rewardTokenContract, dbcAIProxy, slashToAddress, projectName)
            )
        );
        console.log("owner:", initialOwner);
        return (proxy, logic);
    }
}
