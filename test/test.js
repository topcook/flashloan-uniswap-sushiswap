const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { constants, getSigners, Contract } = ethers;
const { WeiPerEther } = constants;
const { computeProfitMaximizingTradeBN, computeProfitMaximizingTrade } = require("../utils");
const ERC20 = require("@uniswap/v2-periphery/build/ERC20.json")
const WETH9 = require("@uniswap/v2-periphery/build/WETH9.json")
const UniswapV2Router = require("@uniswap/v2-periphery/build/UniswapV2Router01.json")
const UniswapV2Factory = require("@uniswap/v2-core/build/UniswapV2Factory.json")
const UniswapV2Pair = require("@uniswap/v2-core/build/UniswapV2Pair.json")

describe("Arbitrager", function () {
  let owner,
    trader,
    weth,
    token,
    arbitrager,
    advancedAbitrager,
    uniswapFactory,
    uniswapRouter,
    uniswapPair,
    sushiFactory,
    sushiRouter,
    sushiPair;

  async function deployWETH(depositAmount) {
    weth = await waffle.deployContract(owner, WETH9)
    await weth.deposit({ value: depositAmount })
  }

  async function deployToken(mintAmount) {
    token = await waffle.deployContract(owner, ERC20, [mintAmount])
  }

  async function deployDEX(liquidityAmount) {
    const factory = await waffle.deployContract(owner, UniswapV2Factory, [owner.address])
    await factory.deployed()
    const router = await waffle.deployContract(owner, UniswapV2Router, [factory.address, weth.address])
    await router.deployed()
    await factory.createPair(weth.address, token.address)
    const pairAddress = await factory.getPair(weth.address, token.address)
    const pair = new Contract(pairAddress, JSON.stringify(UniswapV2Pair.abi), owner)

    // Add liquidity
    await weth.connect(owner).transfer(pairAddress, liquidityAmount)
    await token.connect(owner).transfer(pairAddress, liquidityAmount)
    await pair.connect(owner).mint(owner.address)
    return { factory, router, pair }
  }

  before("Deploy contracts", async function () {
    const accounts = await getSigners();
    owner = accounts[0];
    trader = accounts[1];
    // Deploy tokens
    await deployWETH(WeiPerEther.mul(300));
    await deployToken(WeiPerEther.mul(300));
    // Deploy exchanges
    const uniswap = await deployDEX(WeiPerEther.mul(100));
    const sushi = await deployDEX(WeiPerEther.mul(100));
    uniswapFactory = uniswap.factory;
    uniswapRouter = uniswap.router;
    uniswapPair = uniswap.pair;
    sushiFactory = sushi.factory;
    sushiRouter = sushi.router;
    sushiPair = sushi.pair;
    // Deploy arbitrager
    const Arbitrager = await ethers.getContractFactory("Arbitrager");
    arbitrager = await Arbitrager.deploy(weth.address);
    await arbitrager.deployed();
    const AdvancedArbitrager = await ethers.getContractFactory("AdvancedArbitrager");
    advancedAbitrager = await AdvancedArbitrager.deploy(weth.address, weth.address, weth.address);
    await advancedAbitrager.deployed();

    await sushiRouter.swapExactETHForTokens(0, [weth.address, token.address], owner.address, 2655527338, { value: ethers.utils.parseEther("1") });
  });

  describe("Main Task", function () {
    const gasprice = ethers.BigNumber.from("1111043189");
    const gas = ethers.BigNumber.from("301443");
    it("gas estimation, price disparity, amount of ETH to maximize profit", async function () {  
      const consoleLogs = []
      const uReserve = await uniswapPair.getReserves();
      const sReserve = await sushiPair.getReserves();
      let uReserveEth, uReserveTkn, sReserveEth, sReserveTkn
      if (weth.address < token.address) {
        uReserveEth = uReserve._reserve0;
        uReserveTkn = uReserve._reserve1;
        sReserveEth = sReserve._reserve0;
        sReserveTkn = sReserve._reserve1;
      } else {
        uReserveEth = uReserve._reserve1;
        uReserveTkn = uReserve._reserve0;
        sReserveEth = sReserve._reserve1;
        sReserveTkn = sReserve._reserve0;
      }
      const result = await computeProfitMaximizingTradeBN(sReserveEth, sReserveTkn, uReserveEth, uReserveTkn);
      let resultOk = true;
      if (result.x.gt(0)) {
        if (result.x.gt(uReserveTkn)) {
          resultOk = false;
        }
        if (result.y.gt(sReserveEth)) {
          resultOk = false;
        }
      } else {
        if (result.x.lt((sReserveTkn).mul(-1))) {
          resultOk = false;
        }
        if (result.y.lt((uReserveEth).mul(-1))) {
          resultOk = false;
        }
      }
      if (!resultOk) {
        // ignoring result that doesn't make sense
        consoleLogs.push(`Result doesn't make sense`);
        await expect(arbitrager.connect(trader).arbitrage(token.address, result.x.gt(0) ? uniswapFactory.address : sushiFactory.address, result.x.gt(0) ? sushiFactory.address : uniswapFactory.address, { value: result.x }))
            .to.be.revertedWith(`No profit`);
      } else {
        const signChange = ethers.BigNumber.from(result.x.gt(0) ? 1 : -1);
        if (result.profit.mul(signChange).gt(0)) {
          consoleLogs.push(
            `X: ${ethers.utils.formatUnits(
              result.x.mul(signChange))} tkn (from ${result.x.gt(0) ? "Uniswap" : "Sushiswap"
            })`,
          );
          consoleLogs.push(
            `Y: ${ethers.utils.formatUnits(
              result.y.mul(signChange))} eth (to ${result.x.gt(0) ? "Sushiswap" : "Uniswap"})`,
          );
          consoleLogs.push(
            `Z: ${ethers.utils.formatUnits(
              result.z.mul(signChange))} eth (entry)`,
          );
          consoleLogs.push(
            `Theoretical Profit: ${ethers.utils.formatUnits(
              result.profit.mul(signChange))} eth`,
          );
          if( result.profit.lt(gas.mul(gasprice))){
            consoleLogs.push(`Result is not profitable considering gas cost`);
            await expect(arbitrager.connect(trader).arbitrage(token.address, result.x.gt(0) ? uniswapFactory.address : sushiFactory.address, result.x.gt(0) ? sushiFactory.address : uniswapFactory.address, { value: result.x }))
            .to.be.revertedWith(`No profit`);
          } else {
            const estimation = await arbitrager.estimateGas.arbitrage(token.address, result.x.gt(0) ? uniswapFactory.address : sushiFactory.address, result.x.gt(0) ? sushiFactory.address : uniswapFactory.address, { value: result.x });
            await arbitrager.setGasUsed(estimation);
            const bal0 = ethers.utils.formatEther(await ethers.provider.getBalance(trader.address));
            await arbitrager.connect(trader).arbitrage(token.address, result.x.gt(0) ? uniswapFactory.address : sushiFactory.address, result.x.gt(0) ? sushiFactory.address : uniswapFactory.address, { value: result.x });
            const bal1 = ethers.utils.formatEther(await ethers.provider.getBalance(trader.address))
            consoleLogs.push(`Actual Profit: ${bal1 - bal0}`);
            consoleLogs.push(`Gas estimation: ${ethers.BigNumber.from(estimation).toNumber()}`);
            consoleLogs.push(`ETH to maximize profit: ${ethers.utils.formatUnits(result.z.mul(signChange))}`);
            expect(bal1-bal0).to.be.above(0);
          }
        } else {
          consoleLogs.push(`Result is not profitable`);
          await expect(arbitrager.connect(trader).arbitrage(token.address, result.x.gt(0) ? uniswapFactory.address : sushiFactory.address, result.x.gt(0) ? sushiFactory.address : uniswapFactory.address, { value: result.x }))
            .to.be.revertedWith(`No profit`);
        }
      }
      var ok = false;
      var res;
      var sREth=100, sRTkn=100, uREth=100, uRTkn=100
      while(!ok){
        res = await computeProfitMaximizingTrade(sREth, sRTkn, uREth, uRTkn);
        if(res.x>0 && res.profit > ethers.utils.formatEther(gas.mul(gasprice))){
          ok = true;
        } else {
          sREth+=0.00001;
        }
      }
      consoleLogs.push(`Minimum price disparity: ${sREth/sRTkn-uREth/uRTkn} eth/tkn`);
      console.log(consoleLogs.join("\n"));
    })
  })
  describe("Additional Challenges", function () {
    it("support arbitrary token pairs, flash swap", async function () {
      await advancedAbitrager.connect(trader).arbitrage(
        token.address,
        weth.address,
        uniswapPair.address,
        sushiPair.address
      );
    });
    it("profit-sharing", async () => {
      expect(Number(ethers.utils.formatEther(await advancedAbitrager.profits(trader.address, weth.address)))).to.above(0)
    })
  })

});
