//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "./libraries/UniswapV2Library.sol";
import "hardhat/console.sol";

contract Arbitrager {
    IWETH public immutable weth;

    constructor(address weth_) {
        weth = IWETH(weth_);
    }

    /*
     * @notice Arbitrages weth/token pair between two exchanges. Returning more
     *         Ether than was passed to the function or reverting.
     * @param token The address of the token that WETH is exchanged for.
     * @param factoryA The UniswapV2Factory for the exchange where WETH is swapped for the token.
     * @param factoryB The UniswapV2Factory for the exchange where the token is swapped for WETH.
     */
    function arbitrage(
        address token,
        address factoryA,
        address factoryB
    ) external payable {
        require(msg.value > 0, "No value");
        weth.deposit{ value: msg.value }();
        // TODO: Handle arbitrage functionality and ensure profitability
    }
}
