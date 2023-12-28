// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20Meme} from "../src/ERC20Meme.sol";

contract InitializeTest is Test {
    function testInitialize() public {
        // deploy the contract.
        ERC20Meme token = new ERC20Meme("Meme token", "MTK", 200e6);

        // contract has all supply.
        uint256 decimalConst = 10 ** token.decimals();

        uint256 totalSupply = 200e6 * decimalConst;

        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.balanceOf(address(token)), token.totalSupply());

        // initialize the trading.
        vm.deal(address(this), 1000 ether);

        token.initialize{value: 1000 ether}();

        // now allocate with owner reverts.
        vm.expectRevert("!initialized");

        vm.deal(address(this), 1000 ether);

        token.initialize{value: 1000 ether}();
    }
}
