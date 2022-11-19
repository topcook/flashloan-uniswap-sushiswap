# Simple Flashloan Contract

This is only for test, not for production.

### Main Task
[Arbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/Arbitrager.sol)<br>
[test](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test.js):

### Additional Challenges
  1. Modify the contract to support arbitrary token pairs.
      >✅smart contrats: [AdvancedArbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/AdvancedArbitrager.sol)->arbitrage()<br>
      >✅unit tests: [test.js](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test.js)
  2. Modify the contract to support multiple exchange interfaces (e.g. Uniswap V3, Balancer, 1Inch, etc.)
      >Support of UniswapV3 <br>
      >✅smart contracts: [AdvancedArbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/AdvancedArbitrager.sol)->normalArbitrageUniswapV2ToUniswapV3()<br>
      >✅unit tests: [test.js](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test.js)
  3. Make the contract ownable and then have the contract use it's own funds for trading. Provide profit-sharing incentives to users who call the `arbitrage()` function.
      >✅smart contrats: [AdvancedArbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/AdvancedArbitrager.sol) -> prfits, owner<br>
      >✅unit tests: [test.js](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test.js)
  4. Add support for gas station network and use profits to pay for the gas costs.
      >✅smart contrats
      [TokenPaymaster.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/TokenPaymaster.sol), [AdvancedArbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/AdvancedArbitrager.sol)<br>
      >✅uint tests: install GSN env and test the integration in [test-gsn.js](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test-gsn.js)
  5. Integrate flash loans to maximize profit.
      >Integrate flash swap<br>
      >✅smart contracts: [AdvancedArbitrager.sol](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/contracts/AdvancedArbitrager.sol)->uniswapV2Call<br>
      >✅unit tests: [test.js](https://github.com/topcook/flashloan-uniswap-sushiswap/blob/main/test/test.js)

## How to test

### Install
```
yarn
```

### Install modules
```
yarn install
```

### Test without gsn
```
yarn test
```
### Test with gsn
```
yarn hardhat-node
```
>open anthother terminal
```
yarn test-gsn
```
