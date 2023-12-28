// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ERC20Meme} from "../src/ERC20Meme.sol";

contract ERC20MemeTest is Test {
    ERC20Meme internal token;
    IUniswapV2Router02 internal router;

    function setUp() public {
        vm.deal(address(this), 1000 ether);

        token = new ERC20Meme("Meme token", "MTK", 200e6);

        router = token.router();

        token.initialize{value: 1000 ether}();
    }

    function withDecimals(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** token.decimals();
    }

    function addLiquidity(address addr, uint256 amountETHDesired, uint256 amountTokenDesired) internal {
        vm.deal(addr, amountETHDesired);

        vm.prank(addr);

        token.approve(address(router), amountTokenDesired);

        vm.prank(addr);

        router.addLiquidityETH{value: amountETHDesired}(address(token), amountTokenDesired, 0, 0, addr, block.timestamp);
    }

    function removeLiquidity(address addr) internal {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(token), router.WETH()));

        uint256 liquidity = pair.balanceOf(addr);

        vm.prank(addr);

        pair.approve(address(router), liquidity);

        vm.prank(addr);

        router.removeLiquidityETHSupportingFeeOnTransferTokens(address(token), liquidity, 0, 0, addr, block.timestamp);
    }

    function buyToken(address addr, uint256 amountETHExact) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        vm.deal(addr, amountETHExact);

        vm.prank(addr);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountETHExact}(0, path, addr, block.timestamp);
    }

    function sellToken(address addr, uint256 exactTokenAmount) internal {
        vm.prank(addr);

        token.approve(address(router), exactTokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(exactTokenAmount, 0, path, addr, block.timestamp);
    }

    receive() external payable {}
}
