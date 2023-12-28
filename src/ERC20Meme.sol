// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @title ERC20 meme
/// @author @niera26
/// @notice meme token with max wallet and taxes at launch
/// @notice source: https://github.com/niera26/erc20-meme-contracts
contract ERC20Meme is Ownable, ERC20, ERC20Burnable {
    // =========================================================================
    // dependencies.
    // =========================================================================

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // sushiswap on arbitrum

    // =========================================================================
    // launch max wallet.
    // =========================================================================

    uint256 public startBlock;

    mapping(address => bool) public pairs;

    uint256 public maxWallet = type(uint256).max; // set to 2% in initialize

    // =========================================================================
    // launch fees.
    // =========================================================================

    address public marketing;

    uint24 public constant maxSwapFee = 3000;
    uint24 public constant feeDenominator = 10000;

    uint24 public buyFee = 2400;
    uint24 public sellFee = 2400;

    // =========================================================================
    // events.
    // =========================================================================

    event Sweep(address indexed addr, address indexed token, uint256 amount);

    // =========================================================================
    // constructor.
    // =========================================================================

    constructor(string memory name, string memory symbol, uint256 _totalSupply)
        Ownable(msg.sender)
        ERC20(name, symbol)
    {
        // marketing wallet is deployer by default.
        marketing = msg.sender;

        // mint total supply to itself.
        _mint(address(this), _totalSupply * 10 ** decimals());
    }

    // =========================================================================
    // exposed user functions.
    // =========================================================================

    /**
     * Swap the collected tax to ETH.
     *
     * Pass minimal expected amount to prevent slippage/frontrun.
     */
    function swapCollectedTax(uint256 amountOutMin) public {
        // return if no tax collected.
        uint256 amountIn = balanceOf(address(this));

        if (amountIn == 0) return;

        // approve router to spend tokens.
        _approve(address(this), address(router), amountIn);

        // swap the whole amount to eth directly to marketing wallet.
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, marketing, block.timestamp
        );
    }

    /**
     * Sweep any other ERC20 mistakenly sent to this contract.
     */
    function sweep(IERC20 otherToken) external {
        require(address(otherToken) != address(this), "!sweep");

        uint256 amount = otherToken.balanceOf(address(this));

        otherToken.transfer(msg.sender, amount);

        emit Sweep(msg.sender, address(otherToken), amount);
    }

    // =========================================================================
    // exposed admin functions.
    // =========================================================================

    /**
     * Initialize the trading with the given eth and this contract balance.
     *
     * Starts trading, sets max wallet to 2% of the supply, create the uniswap V2 pair
     * with ETH, adds liquidity.
     *
     * LP tokens are sent to owner.
     */
    function initialize() external payable onlyOwner {
        require(msg.value > 0, "!liquidity");
        require(startBlock == 0, "!initialized");

        // set start block so cant be initialized twice.
        startBlock = block.number;

        // init max wallet to 2%.
        maxWallet = totalSupply() / 50;

        // the all balance will be put in the LP.
        uint256 balance = balanceOf(address(this));

        // create an amm pair with WETH.
        // as a contract, pair is automatically excluded from rewards.
        createAmmPairWith(router.WETH());

        // approve router to use total balance.
        _approve(address(this), address(router), balance);

        // add liquidity and send LP to owner.
        router.addLiquidityETH{value: msg.value}(address(this), balance, 0, 0, msg.sender, block.timestamp);
    }

    /**
     * Remove max wallet limits, one shoot.
     */
    function removeMaxWallet() external onlyOwner {
        maxWallet = type(uint256).max;
    }

    /**
     * Set the fees.
     */
    function setFee(uint24 _buyFee, uint24 _sellFee) external onlyOwner {
        require(_buyFee <= maxSwapFee, "!buyFee");
        require(_sellFee <= maxSwapFee, "!sellFee");

        buyFee = _buyFee;
        sellFee = _sellFee;
    }

    /**
     * Ensure no limitation when renouncing ownership.
     */
    function renounceOwnership() public override onlyOwner {
        require(buyFee == 0, "!buyFee");
        require(sellFee == 0, "!sellFee");
        require(maxWallet == type(uint256).max, "!maxWallet");
        _transferOwnership(address(0));
    }

    // =========================================================================
    // internal functions.
    // =========================================================================

    /**
     * Create a pair between this token and the given token.
     */
    function createAmmPairWith(address token) private {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.createPair(token, address(this));

        pairs[pair] = true;
    }

    /**
     * Whether the given address is excluded from max wallet limit.
     */
    function _isExcludedFromMaxWallet(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr || pairs[addr];
    }

    /**
     * Whether the given adress is excluded from taxes.
     */
    function _isExcludedFromTaxes(address addr) private view returns (bool) {
        return address(this) == addr || address(router) == addr;
    }

    /**
     * Override the update method in order to take fee when the transfer is from/to
     * a registered amm pair and to prevent max wallet.
     *
     * - transfers from/to registered pairs are taxed.
     * - taxed tokens are sent to this very contract.
     * - on a taxed sell, the collected tax is swapped for eth.
     * - prevents receiving address to get more than max wallet.
     */
    function _update(address from, address to, uint256 amount) internal override {
        // check if it is a taxed buy/sell.
        bool isTaxedBuy = pairs[from] && !_isExcludedFromTaxes(to);
        bool isTaxedSell = !_isExcludedFromTaxes(from) && pairs[to];

        // compute the fee of a taxed buy/sell.
        uint256 fee = (isTaxedBuy ? buyFee : 0) + (isTaxedSell ? sellFee : 0);

        uint256 taxAmount = (amount * fee) / feeDenominator;

        uint256 actualTransferAmount = amount - taxAmount;

        // transfer the tax to this contract.
        if (taxAmount > 0) {
            super._update(from, address(this), taxAmount);
        }

        // swaps the tax to eth when it is a sell.
        if (isTaxedSell) {
            swapCollectedTax(0);
        }

        // transfer the actual amount to receiving address.
        super._update(from, to, actualTransferAmount);

        // revert when the receiving address balance is above max wallet.
        if (!_isExcludedFromMaxWallet(to)) {
            require(balanceOf(to) <= maxWallet, "!maxWallet");
        }
    }
}
