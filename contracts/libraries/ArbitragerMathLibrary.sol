// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uniswap/lib/contracts/libraries/Babylonian.sol";

// library containing some math for dealing with the liquidity shares of a pair, e.g. computing their exact value
// in terms of the underlying tokens
library ArbitragerMathLibrary {
    
    function calX(
        uint256 Ares0,
        uint256 Ares1,
        uint256 Bres0,
        uint256 Bres1
    ) internal pure returns (int256) {
        int256 prA = int256(Babylonian.sqrt(Ares0 * Ares1));
        int256 prB = int256(Babylonian.sqrt(Bres0 * Bres1));
        int256 x = ((((int256(Ares1) * 1000 + int256(Bres1) * 997) *
            (prA - prB)) / (prA + prB)) -
            (int256(Ares1) * 1000 - int256(Bres1) * 997)) /
            2 /
            997;
        return x;
    }

    function computeProfitMaximizingTrade(
        uint256 Ares0,
        uint256 Ares1,
        uint256 Bres0,
        uint256 Bres1
    )
        internal
        pure
        returns (
            uint256 x,
            uint256 y,
            uint256 z
        )
    {
        int256 _x = calX(Ares0, Ares1, Bres0, Bres1);
        if (_x <= 0 || x >= Bres1 || y >= Ares0) {
            return (0, 0, 0);
        }
        x = uint256(_x);

        y = ((x * 997 * Ares0)) / (Ares1 * 1000 + x * 997);
        z = ((((Bres0 * x) * 1000) / (Bres1 - x))) / 997;
    }

    function sqrt(uint256 _x) public pure returns (uint256) {
        int256 x = int256(_x);
        int256 z = (x + 1) / 2;
        int256 y = x;
        while (z - y < 0) {
            y = z;
            z = ((x / z) + z) / (2);
        }
        return uint256(y);
    }
}
