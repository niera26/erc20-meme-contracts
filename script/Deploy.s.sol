// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {ERC20Meme} from "../src/ERC20Meme.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        new ERC20Meme("Meme token", "MTK", 200e6);
        vm.stopBroadcast();
    }
}
