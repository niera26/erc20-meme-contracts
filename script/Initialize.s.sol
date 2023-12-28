// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {ERC20Meme} from "../src/ERC20Meme.sol";

contract Initialize is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ERC20MemeAddress = vm.envAddress("ERC20_MEME_ADDRESS");

        ERC20Meme token = ERC20Meme(payable(ERC20MemeAddress));

        vm.startBroadcast(deployerPrivateKey);
        token.initialize{value: 1000 ether}();
        vm.stopBroadcast();
    }
}
