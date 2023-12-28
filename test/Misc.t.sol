// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20MemeTest} from "./ERC20MemeTest.t.sol";

contract ERC20Mock is ERC20 {
    constructor(uint256 _totalSupply) ERC20("R", "R") {
        _mint(msg.sender, _totalSupply);
    }
}

contract MiscTest is ERC20MemeTest {
    function testRenounceOwnership() public {
        address user = vm.addr(1);

        // ensure we can sell after renouncing ownership.
        buyToken(user, 1 ether);

        assertGt(token.balanceOf(address(token)), 0);
        assertEq(token.marketing().balance, 0);

        // by default owner is deployer.
        assertEq(token.owner(), address(this));

        // owner cant renounce ownership with a buy fee.
        vm.expectRevert("!buyFee");

        token.renounceOwnership();

        token.setFee(0, 2400);

        // owner cant renounce ownership with a sell fee.
        vm.expectRevert("!sellFee");

        token.renounceOwnership();

        token.setFee(0, 0);

        // owner cant renounce ownership with a max wallet.
        vm.expectRevert("!maxWallet");

        token.renounceOwnership();

        token.removeMaxWallet();

        // user cant renounce ownership.
        vm.prank(user);

        vm.expectRevert();

        token.renounceOwnership();

        // owner can renounce ownership.
        token.renounceOwnership();

        assertEq(token.owner(), address(0));

        // sell the user tokens.
        sellToken(user, token.balanceOf(address(user)));

        assertEq(token.balanceOf(address(token)), 0);
        assertGt(token.marketing().balance, 0);

        uint256 originalMarketingBalance = token.marketing().balance;

        // no more taxes.
        buyToken(user, 1 ether);

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.marketing().balance, originalMarketingBalance);

        sellToken(user, token.balanceOf(address(user)));

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.marketing().balance, originalMarketingBalance);
    }

    function testRemoveMaxWallet() public {
        address user = vm.addr(1);

        // by default max wallet is 2% of the supply.
        assertEq(token.maxWallet(), token.totalSupply() / 50);

        // non owner reverts.
        vm.prank(user);

        vm.expectRevert();

        token.removeMaxWallet();

        // owner can remove max wallet.
        token.removeMaxWallet();

        assertEq(token.maxWallet(), type(uint256).max);
    }

    function testSetFee() public {
        address user = vm.addr(1);

        uint24 maxSwapFee = token.maxSwapFee();

        // default fee is 24%, 24%
        assertEq(token.buyFee(), 2400);
        assertEq(token.sellFee(), 2400);

        // non owner reverts.
        vm.prank(user);

        vm.expectRevert();

        token.setFee(101, 102);

        // owner can set fee.
        token.setFee(101, 102);

        assertEq(token.buyFee(), 101);
        assertEq(token.sellFee(), 102);

        // more than max fee reverts.
        vm.expectRevert("!buyFee");
        token.setFee(maxSwapFee + 1, 0);

        vm.expectRevert("!sellFee");
        token.setFee(0, maxSwapFee + 1);
    }

    function testBuySellTax() public {
        address user = vm.addr(1);

        // put random taxes.
        token.setFee(1000, 2000);

        buyToken(user, 1 ether);

        uint256 balance = token.balanceOf(user);

        // 10% was taken on buy (so we have 90% of tokens).
        uint256 buyTax = balance / 9;

        // 20% will be taken on sell.
        uint256 sellTax = balance / 5;

        assertApproxEqRel(token.balanceOf(address(token)), buyTax, 0.01e18);

        sellToken(user, balance);

        assertEq(token.balanceOf(address(token)), 0);
        assertApproxEqRel(address(token.marketing()).balance, (buyTax + sellTax) / 200000, 0.01e18);
    }

    function testMaxWallet() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);
        address user4 = vm.addr(4);

        // cant buy more than 2% of supply by default.
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.deal(user1, 28 ether);

        vm.prank(user1);

        vm.expectRevert("UniswapV2: TRANSFER_FAILED");

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 28 ether}(0, path, user1, block.timestamp);

        // user cant be transfered more than 2% of supply.
        buyToken(user2, 1 ether);
        buyToken(user3, 27 ether);

        uint256 balance1 = token.balanceOf(user2);
        uint256 balance2 = token.balanceOf(user3);

        vm.prank(user2);

        token.transfer(user4, balance1);

        vm.prank(user3);

        vm.expectRevert("!maxWallet");

        token.transfer(user4, balance2);

        // after removing limits it is working.
        token.removeMaxWallet();

        buyToken(user1, 29 ether);

        assertGt(token.balanceOf(user1), token.totalSupply() / 50);

        vm.prank(user3);

        token.transfer(user4, balance2);

        assertGt(token.balanceOf(user4), token.totalSupply() / 50);
    }

    function testBurn() public {
        address user = vm.addr(1);

        uint256 totalSupply = token.totalSupply();

        buyToken(user, 1 ether);

        uint256 userBalance = token.balanceOf(user);
        uint256 contractBalance = token.balanceOf(address(token));

        // partial burn.
        uint256 amountToBurn = userBalance / 2;
        uint256 remainingAmount = userBalance - amountToBurn;

        vm.prank(user);

        token.burn(amountToBurn);

        assertEq(token.balanceOf(address(user)), remainingAmount);
        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - amountToBurn);

        // total burn.
        vm.prank(user);

        token.burn(remainingAmount);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(token)), contractBalance);
        assertEq(token.totalSupply(), totalSupply - userBalance);
    }

    function testTokenSweep() public {
        IERC20 randomToken = new ERC20Mock(1000);

        address user = vm.addr(1);

        // put token in the contract.
        buyToken(user, 1 ether);

        uint256 userBalance = token.balanceOf(address(user));

        vm.prank(user);

        token.transfer(address(token), userBalance);

        assertGt(token.balanceOf(address(token)), userBalance);

        // owner cant sweep token.
        vm.expectRevert("!sweep");

        token.sweep(token);

        // user cant sweep token.
        vm.prank(user);

        vm.expectRevert("!sweep");

        token.sweep(token);

        // owner can sweep random token.
        randomToken.transfer(address(token), 1000);

        assertEq(randomToken.balanceOf(address(this)), 0);
        assertEq(randomToken.balanceOf(address(token)), 1000);

        token.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(this)), 1000);
        assertEq(randomToken.balanceOf(address(token)), 0);

        // user can sweep random token.
        randomToken.transfer(address(token), 1000);

        assertEq(randomToken.balanceOf(address(user)), 0);
        assertEq(randomToken.balanceOf(address(token)), 1000);

        vm.prank(user);

        token.sweep(randomToken);

        assertEq(randomToken.balanceOf(address(user)), 1000);
        assertEq(randomToken.balanceOf(address(token)), 0);
    }
}
