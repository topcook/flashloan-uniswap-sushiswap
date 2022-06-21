const { expect } = require("chai");
const ethers = require("ethers");
const ERC20 = require("@uniswap/v2-periphery/build/ERC20.json")
const WETH9 = require("@uniswap/v2-periphery/build/WETH9.json")
const UniswapV2Router = require("@uniswap/v2-periphery/build/UniswapV2Router01.json")
const UniswapV2Factory = require("@uniswap/v2-core/build/UniswapV2Factory.json")
const UniswapV2Pair = require("@uniswap/v2-core/build/UniswapV2Pair.json")

const { RelayProvider } = require('@opengsn/provider')
const { GsnTestEnvironment } = require('@opengsn/dev')

const Web3HttpProvider = require('web3-providers-http')
const AdvancedArbitrager = require('../artifacts/contracts/AdvancedArbitrager.sol/AdvancedArbitrager')
const TokenPaymaster = require('../artifacts/contracts/TokenPaymaster.sol/TokenPaymaster')

describe("GSN Test", function () {
  let deployer,
    ethlessAcc,
    weth,
    token,
    abitrager,
    uniswapFactory,
    uniswapRouter,
    uniswapPair,
    sushiFactory,
    sushiRouter,
    sushiPair,
    web3provider,
    paymaster,
    gsnEthersProvider;

  async function deployWETH(depositAmount) {
    const WETH9Factory = new ethers.ContractFactory(WETH9.abi, WETH9.bytecode, deployer)
    weth = await WETH9Factory.deploy()
    await weth.deployed()
    await weth.deposit({ value: depositAmount })
  }

  async function deployToken(mintAmount) {
    const ERC20Factory = new ethers.ContractFactory(ERC20.abi, ERC20.bytecode, deployer)
    token = await ERC20Factory.deploy(mintAmount)
    await token.deployed()
  }

  async function deployDEX(liquidityAmount) {
    const uniswapV2Factory = new ethers.ContractFactory(UniswapV2Factory.abi, UniswapV2Factory.bytecode, deployer)
    const factory = await uniswapV2Factory.deploy(await deployer.getAddress())
    await factory.deployed()

    const uniswapV2Router = new ethers.ContractFactory(UniswapV2Router.abi, UniswapV2Router.bytecode, deployer)
    const router = await uniswapV2Router.deploy(factory.address, weth.address)
    await router.deployed()

    await factory.createPair(weth.address, token.address)
    const pairAddress = await factory.getPair(weth.address, token.address)
    const pair = new ethers.Contract(pairAddress, JSON.stringify(UniswapV2Pair.abi), deployer)

    // Add liquidity
    await weth.connect(deployer).transfer(pairAddress, liquidityAmount)
    await token.connect(deployer).transfer(pairAddress, liquidityAmount)
    await pair.connect(deployer).mint(await deployer.getAddress())
    return { factory, router, pair }
  }

  before("Deploy contracts and install GSN environment", async function () {
    web3provider = new Web3HttpProvider('http://localhost:8545')
    const deploymentProvider = new ethers.providers.Web3Provider(web3provider)
    deployer = deploymentProvider.getSigner();

    // Deploy tokens
    await deployWETH(ethers.constants.WeiPerEther.mul(300));
    await deployToken(ethers.constants.WeiPerEther.mul(300));
    // Deploy exchanges
    const uniswap = await deployDEX(ethers.constants.WeiPerEther.mul(100));
    const sushi = await deployDEX(ethers.constants.WeiPerEther.mul(100));
    uniswapFactory = uniswap.factory;
    uniswapRouter = uniswap.router;
    uniswapPair = uniswap.pair;
    sushiFactory = sushi.factory;
    sushiRouter = sushi.router;
    sushiPair = sushi.pair;

    //start gsn server
    let env = await GsnTestEnvironment.startGsn('localhost')

    const { relayHubAddress, forwarderAddress } = env.contractsDeployment

    //deploy paymaster
    const TokenPaymasterFactory = new ethers.ContractFactory(TokenPaymaster.abi, TokenPaymaster.bytecode, deployer)
    paymaster = await TokenPaymasterFactory.deploy([uniswapRouter.address, sushiRouter.address], weth.address)
    await paymaster.deployed()

    //deploy abitrager
    const AdvancedArbitragerFactory = new ethers.ContractFactory(AdvancedArbitrager.abi, AdvancedArbitrager.bytecode, deployer)
    abitrager = await AdvancedArbitragerFactory.deploy(weth.address, forwarderAddress, paymaster.address)
    await abitrager.deployed()

    //configure paymaster
    await paymaster.setRelayHub(relayHubAddress)
    await paymaster.setTrustedForwarder(forwarderAddress)
    await paymaster.getHubAddr()
    await paymaster.depositEthToHub({value: ethers.utils.parseEther("1")})

    await abitrager.approveAll(weth.address, paymaster.address);
    await weth.deposit({value: ethers.utils.parseEther("1")});
    await weth.transfer(abitrager.address, ethers.utils.parseEther("1"));

    await sushiRouter.swapExactETHForTokens(0, [weth.address, token.address], await deployer.getAddress(), 2655527338, { value: ethers.utils.parseEther("1") });

  });

  describe("Additional Challenges", function () {
    before("Set up gsn provider", async()=>{
      const config = {
        // loggerConfiguration: { logLevel: 'error'},
        paymasterAddress: paymaster.address,
        auditorsCount: 0
      }
      const asyncPaymasterData = async function (relayRequest) {
        return Promise.resolve(ethers.utils.defaultAbiCoder.encode(["address","address"],[weth.address, uniswapRouter.address]))
      }
      let gsnProvider = RelayProvider.newProvider({ provider: web3provider, config, overrideDependencies:{ asyncPaymasterData } })
      await gsnProvider.init()
      gsnEthersProvider = new ethers.providers.Web3Provider(gsnProvider)
    })

    it("create ethless account", async () => {
      const acct = gsnEthersProvider.provider.newAccount()
      ethlessAcc = gsnEthersProvider.getSigner(acct.address)
      expect(await gsnEthersProvider.getBalance(acct.address)).to.equal(0)
    })
    it("use profits to pay for the gas costs when doing arbitrage", async () => {
      const ethlessAccAddr = await ethlessAcc.getAddress();
      expect(Number(ethers.utils.formatEther(await abitrager.profits(ethlessAccAddr, token.address)))).to.equal(0);
      const transaction = await abitrager.connect(ethlessAcc).arbitrage(token.address, weth.address, uniswapPair.address, sushiPair.address);
      const receipt = await gsnEthersProvider.waitForTransaction(transaction.hash);
      console.log("result", receipt);
      const balance = await abitrager.profits(ethlessAccAddr, weth.address);
      expect(Number(ethers.utils.formatEther(balance))).to.above(0);
    })
  })

});
