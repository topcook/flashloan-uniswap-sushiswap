// SPDX-License-Identifier:MIT
pragma solidity ^0.8.6;

interface IArbitrager {
  function cutGsnGas(address target, address token, uint amount) external;
}