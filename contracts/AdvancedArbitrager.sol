// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@opengsn/contracts/src/BaseRelayRecipient.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libraries/UniswapV2Library.sol";
import "./libraries/ArbitragerMathLibrary.sol";

contract AdvancedArbitrager is IUniswapV2Callee, BaseRelayRecipient {
    IWETH public immutable weth;
    uint256 public fee = 3;
    address public owner;
    address public paymaster;
    bool private locked;

    //user => token => amount
    mapping(address => mapping(address => uint256)) public profits; //sharing of profits

    mapping(address => mapping(address => uint256)) public gasCosts;

    modifier onlyOwner() {
        require(msg.sender == owner, "not an owner");
        _;
    }

    modifier lock() {
        require(!locked, "LOK");
        locked = true;
        _;
        locked = false;
    }

    constructor(
        address weth_,
        address forwarder_,
        address paymaster_
    ) {
        owner = _msgSender();
        weth = IWETH(weth_);
        _setTrustedForwarder(forwarder_);
        paymaster = paymaster_;
    }

    function versionRecipient() external pure override returns (string memory) {
        return "2.2.1";
    }

    receive() external payable {}

    function arbitrage(
        address pullToken,
        address remainToken,
        address pairA, // address exchangeA, // swap
        address pairB // address exchangeB, // flash
    ) public {
        require(pairA != pairB, "both exchange same");
        // evaluate if trade is profitable
        // address pairA = IUniswapV2Factory(exchangeA).getPair(pullToken, remainToken);
        // address pairB = IUniswapV2Factory(exchangeB).getPair(pullToken, remainToken);
        bool pullTokenIs0 = uint160(pullToken) < uint160(remainToken);
        uint256 x;
        uint256 y;
        uint256 z;
        {
            uint256 reserveAPull;
            uint256 reserveARemain;
            uint256 reserveBpull;
            uint256 reserveBremain;

            // these are not exactly pull and remain tokens, they are swapped below if necessary
            (reserveAPull, reserveARemain, ) = IUniswapV2Pair(pairA)
                .getReserves();
            (reserveBpull, reserveBremain, ) = IUniswapV2Pair(pairB)
                .getReserves();

            // swapping if pulltoken - remaintoken is different than uniswap's 0 - 1 order.
            if (!pullTokenIs0) {
                (reserveAPull, reserveARemain) = (reserveARemain, reserveAPull);
                (reserveBpull, reserveBremain) = (reserveBremain, reserveBpull);
            }

            require(
                reserveAPull > 0 &&
                    reserveARemain > 0 &&
                    reserveBpull > 0 &&
                    reserveBremain > 0,
                "No Liquidity"
            );

            (x, y, z) = ArbitragerMathLibrary.computeProfitMaximizingTrade(
                reserveBremain,
                reserveBpull,
                reserveARemain,
                reserveAPull
            );
        }

        // emit TradeCalculated(x, y, z);
        require(x != 0, "Trade is not profitable");

        //
        // trigger flash loan
        IUniswapV2Pair(pairA).swap(
            pullTokenIs0 ? x : 0,
            pullTokenIs0 ? 0 : x,
            address(this),
            abi.encode(pairB, pullToken, remainToken, y, z)
        );

        // //
        // // store profits to profit address
        profits[_msgSender()][remainToken] += ((y - z - 1) * fee) / 100;
        profits[owner][remainToken] += ((y - z - 1) * (100 - fee)) / 100;
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        bool pullTokenIs0 = amount0 > 0;
        uint256 x = pullTokenIs0 ? amount0 : amount1;

        (
            address pairB,
            address pullToken,
            address remainToken,
            uint256 y,
            uint256 z
        ) = abi.decode(data, (address, address, address, uint256, uint256));

        {
            // IERC20(pullToken).transfer(pairB, x);
            (bool success, ) = pullToken.call(
                abi.encodeWithSignature("transfer(address,uint256)", pairB, x)
            );
            require(success, "erc20 transfer 1 failing");
        }
        IUniswapV2Pair(pairB).swap(
            pullTokenIs0 ? 0 : y,
            pullTokenIs0 ? y : 0,
            address(this),
            ""
        );

        {
            // IERC20(remainToken).transfer(pairA, z + 1);
            (bool success, ) = remainToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    z + 1
                )
            );
            require(success, "erc20 transfer 2 failing");
        }
    }

    function normalArbitrageUniswapV2ToUniswapV3(
        address token0,
        address token1,
        IUniswapV2Router02 uniV2Router,
        ISwapRouter uniV3Router,
        uint256 amountIn
    ) external {
        require(amountIn > 0);
        //use token of this contract for arbitrager
        IERC20(token0).approve(address(uniV2Router), amountIn);
        address[] memory pathA = new address[](2);
        (pathA[0], pathA[1]) = (token0, token1);
        uint256[] memory amounts = uniV2Router.swapExactTokensForTokens(
            amountIn,
            type(uint256).max,
            pathA,
            address(this),
            block.timestamp + 60 * 15
        );

        TransferHelper.safeApprove(token1, address(uniV3Router), amounts[1]);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                token1,
                token0,
                3000,
                address(this),
                block.timestamp + 15,
                amounts[1],
                0,
                0
            );
        uint256 amountOut = uniV3Router.exactInputSingle(params);
        require(amountOut > amountIn);
        profits[msg.sender][token0] += amountOut - amountIn;
    }

    function withdraw(address token, address to) external lock {
        uint256 profit = profits[to][token];
        uint256 gasCost = gasCosts[to][token];
        profits[to][token] = 0; // defend reentrancy
        gasCosts[to][token] = 0;
        require(profit > gasCost, "No profit");

        if (token == address(weth)) {
            weth.withdraw(profit);
            TransferHelper.safeTransferETH(to, profit - gasCost);
        } else {
            TransferHelper.safeTransfer(token, to, profit - gasCost);
        }
    }

    function approveAll(address token, address sender) external onlyOwner {
        IERC20(token).approve(sender, type(uint256).max);
    }

    function cutGsnGas(
        address target,
        address token,
        uint256 amount
    ) external {
        require(msg.sender == paymaster, "not a paymaster");
        gasCosts[target][token] = gasCosts[target][token] + amount;
    }
}
