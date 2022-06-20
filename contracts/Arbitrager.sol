// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "hardhat/console.sol";

import "./libraries/UniswapV2Library.sol";
import "./libraries/ArbitragerMathLibrary.sol";

contract Arbitrager {
    IWETH public immutable weth;
    uint256 public gasUsed;
    constructor(address weth_) {
        weth = IWETH(weth_);
    }

    function setGasUsed(uint256 amount) external {
        gasUsed = amount;
    }

    receive() external payable { }
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
        address[] memory pathA = new address[](2);
        address[] memory pathB = new address[](2);
        (pathA[0], pathA[1], pathB[0], pathB[1]) = (
            address(weth),
            token,
            token,
            address(weth)
        );
        uint256[] memory amountsA = UniswapV2Library.getAmountsOut(
            factoryA,
            msg.value,
            pathA
        );
        uint256[] memory amountsB = UniswapV2Library.getAmountsOut(
            factoryB,
            amountsA[1],
            pathB
        );

        weth.deposit{value: msg.value}();
        assert(
            weth.transfer(
                UniswapV2Library.pairFor(factoryA, pathA[0], pathA[1]),
                amountsA[0]
            )
        );
        _swap(factoryA, amountsA, pathA, address(this));
        IERC20(token).approve(address(this), amountsB[0]);
        TransferHelper.safeTransferFrom(
            pathB[0],
            address(this),
            UniswapV2Library.pairFor(factoryB, pathB[0], pathB[1]),
            amountsB[0]
        );
        _swap(factoryB, amountsB, pathB, address(this));
        weth.withdraw(amountsB[1]);
        TransferHelper.safeTransferETH(msg.sender, amountsB[1]);
        require(amountsB[1] > amountsA[0] + gasUsed * tx.gasprice, "No profit");
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        address factory,
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? UniswapV2Library.pairFor(factory, output, path[i + 2])
                : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // function computeProfitMaximizingTrade(
    //     address token,
    //     address factory0,
    //     address factory1
    // ) public view returns (bool aToB, uint256 amountIn) {
    //     uint reserve0A;
    //     uint reserve0B;
    //     uint reserve1A;
    //     uint reserve1B;
    //     (reserve0A, reserve0B) = UniswapV2Library.getReserves(factory0, address(weth), token);
    //     (reserve1A, reserve1B) = UniswapV2Library.getReserves(factory1, address(weth), token);
    //     int256 x = ArbitragerMathLibrary.computeProfitMaximizingTrade(reserve1A, reserve1B, reserve0A, reserve0B);
    //     aToB = x > 0;
    //     if(aToB) {
    //         address[] memory path = new address[](2);
    //         (path[0], path[1]) = (address(weth), token);
    //         uint[] memory amounts = UniswapV2Library.getAmountsIn(factory0, x > 0 ? uint(x): uint(-x), path);
    //         amountIn = amounts[0];
    //     } else {
    //         amountIn = 0;
    //     }
    // }
}
