
const { ethers } = require("ethers");

function calX(Ares0, Ares1, Bres0, Bres1) {
  // product sq.roots
  const prA = Math.sqrt(Ares0 * Ares1);
  const prB = Math.sqrt(Bres0 * Bres1);

  const k = (prA + prB) / (prA - prB);

  const x= ((1 / k) * (Ares1 * (1000 / 997) + Bres1)) / 2 - (Ares1 * (1000 / 997) - Bres1) / 2;
  return x;
}

// export function calProfit(x: number, Ares0: number, Ares1: number, Bres0: number, Bres1: number): number {
//   return Ares0 - (Ares0 * Ares1) / (Ares1 + x) + (Bres0 * Bres1) / (x - Bres1) + Bres0;
// }

function computeProfitMaximizingTrade(Ares0, Ares1, Bres0, Bres1) {
  const x = calX(Ares0, Ares1, Bres0, Bres1);
  // const y = Ares0 - (Ares0 * Ares1) / (Ares1 + x);
  // const z = (Bres0 * Bres1) / (Bres1 - x) - Bres0;
  const y = (x * (997 / 1000) * Ares0) / (Ares1 + x * (997 / 1000));
  const z = (((Bres0 * x) / (Bres1 - x)) * 1000) / 997;
  const profit = y - z;
  return { x, y, z, profit };

}

function calX_BN(
  Ares0,
  Ares1,
  Bres0,
  Bres1,
) {
  // product sq.roots
  const prA = bignumberSqrt(Ares0.mul(Ares1));
  const prB = bignumberSqrt(Bres0.mul(Bres1));

  // k fraction
  const pr_sum = prA.add(prB);
  const pr_diff = prA.sub(prB);
  // console.log("pr_sum.toString(), pr_diff.toString()", pr_sum.toString(), pr_diff.toString());

  // console.log("x1.toString()", x1.toString());

  // const x2 = ((1 / k) * (Ares1 + Bres1)) / 2 - (Ares1 - Bres1) / 2;
  // const x2 = pr_diff.mul(Ares1.add(Bres1)).div(pr_sum.mul(2)).sub(Ares1.sub(Bres1).div(2));
  const x = pr_diff
    .mul(Ares1.mul(1000).add(Bres1.mul(997)))
    .div(pr_sum)
    .add(Bres1.mul(997).sub(Ares1.mul(1000)))
    .div(2)
    .div(997);

  // console.log("x2.toString()", x2.toString());
  return x;
}

function computeProfitMaximizingTradeBN(Ares0, Ares1, Bres0, Bres1) {
  const x = calX_BN(Ares0, Ares1, Bres0, Bres1);
  // console.log(1);
  // const y_pure = Ares0.sub(Ares0.mul(Ares1).div(Ares1.add(x)));
  // const y = y_pure.mul(997).div(1000);
  // const z_pure = Bres0.mul(Bres1).div(Bres1.sub(x)).sub(Bres0);
  // const z = z_pure.mul(1003).div(1000);
  const y = x
    .mul(997)
    .mul(Ares0)
    .div(Ares1.mul(1000).add(x.mul(997)));
  const z = Bres0.mul(x).mul(1000).div(Bres1.sub(x)).div(997);
  const profit = y.sub(z);
  return { x, y, z, profit };

}

const ONE = ethers.BigNumber.from(1);
const TWO = ethers.BigNumber.from(2);

function bignumberSqrt(x) {
  let z = x.add(ONE).div(TWO);
  let y = x;
  while (z.sub(y).isNegative()) {
    y = z;
    z = x.div(z).add(z).div(TWO);
  }
  return y;
}

const getCounter = (networkId) => {
  return {
    4: '0x566B67A276f1a5E8148970e2141ad08F6078B0a3'
  }[networkId];
};

const getPayMaster = (networkId) => {
  return {
    4: '0xA6e10aA9B038c9Cddea24D2ae77eC3cE38a0c016'
  }[networkId];
};

const getRelayHub = (networkId) => {
  return {
    4: '0x6650d69225CA31049DB7Bd210aE4671c0B1ca132'
  }[networkId];
};

const getForwarder = (networkId) => {
  return {
    4: '0x83A54884bE4657706785D7309cf46B58FE5f6e8a'
  }[networkId];
};

const isLocal = (chainId) => {
  return [
    1337, 31337
  ].includes(chainId);
};

module.exports = {
  computeProfitMaximizingTrade,
  computeProfitMaximizingTradeBN,
  address: {
    getCounter,
    getPayMaster,
    getRelayHub,
    getForwarder,
  },
  isLocal
};