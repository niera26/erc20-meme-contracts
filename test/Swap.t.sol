// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20MemeTest} from "./ERC20MemeTest.t.sol";

contract SwapTest is ERC20MemeTest {
    function testSwap() public {
        address user = vm.addr(1);

        // buy 1 ether of tokens.
        buyToken(user, 1 ether);

        // we must have received ~ 152000 tokens and ~ 48000 should be collected as tax.
        assertApproxEqRel(token.balanceOf(user), withDecimals(152000), 0.01e18);
        assertApproxEqRel(token.balanceOf(address(token)), withDecimals(48000), 0.01e18);

        // sell everything, should swapback taxes to eth.
        uint256 balance = token.balanceOf(user);

        sellToken(user, balance);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token.marketing()).balance, 0.4224 ether, 0.01e18);

        // (total tax is 48000 + (152000 * 0.24) = 84480 and 200000 tokens =~ 1 eth)
        // (84480 / 200000 = 0,4224 eth)
    }
}
