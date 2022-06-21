// SPDX-License-Identifier:MIT
pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@opengsn/contracts/src/forwarder/IForwarder.sol";
import "@opengsn/contracts/src/BasePaymaster.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "./interfaces/IArbitrager.sol";

/**
 * A Token-based paymaster.
 * - each request is paid for by the caller.
 * - acceptRelayedCall - verify the caller can pay for the request in tokens.
 * - preRelayedCall - pre-pay the maximum possible price for the tx
 * - postRelayedCall - refund the caller for the unused gas
 */
contract TokenPaymaster is BasePaymaster {

    function versionPaymaster() external override virtual view returns (string memory){
        return "2.2.1";
    }

    IUniswapV2Router02[] public uniswaps;
    // IERC20[] public tokens;
    IWETH public immutable weth;

    mapping (IUniswapV2Router02=>bool ) private supportedUniswaps;

    uint256 public gasUsedByPost;

    constructor(IUniswapV2Router02[] memory _uniswaps, address weth_) {
        uniswaps = _uniswaps;
        weth = IWETH(weth_);

        for (uint256 i = 0; i < _uniswaps.length; i++){
            supportedUniswaps[_uniswaps[i]] = true;
            // tokens.push(IERC20(_uniswaps[i].tokenAddress()));
            // tokens[i].approve(address(_uniswaps[i]), type(uint256).max);
        }
    }

    /**
     * set gas used by postRelayedCall, for proper gas calculation.
     * You can use TokenGasCalculator to calculate these values (they depend on actual code of postRelayedCall,
     * but also the gas usage of the token and of Uniswap)
     */
    function setPostGasUsage(uint256 _gasUsedByPost) external onlyOwner {
        gasUsedByPost = _gasUsedByPost;
    }

    // return the payer of this request.
    // for account-based target, this is the target account.
    function getPayer(GsnTypes.RelayRequest calldata relayRequest) public virtual view returns (address) {
        (this);
        return relayRequest.request.to;
    }

    event Received(uint256 eth);
    receive() external override payable {
        emit Received(msg.value);
    }

    function _getToken(bytes memory paymasterData) internal view returns (IERC20 token, IUniswapV2Router02 uniswap) {
        (address _token, address _uniswap) = abi.decode(paymasterData, (address, address));
        (token, uniswap) = (IERC20(_token), IUniswapV2Router02(_uniswap));
        require(supportedUniswaps[uniswap], "unsupported uniswap");
    }

    function _getAmountIn(IUniswapV2Router02 uniswap, IERC20 token, uint ethCharge) private view returns(uint) {
        if(address(token) == address(weth)) {
            return ethCharge;
        } else {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (address(token), address(weth));
            return uniswap.getAmountsIn(ethCharge, path)[0];
        }
    }

    function _calculatePreCharge(
        IERC20 token,
        IUniswapV2Router02 uniswap,
        GsnTypes.RelayRequest calldata relayRequest,
        uint256 maxPossibleGas)
    internal
    view
    returns (address payer, uint256 tokenPreCharge) {
        (token);
        payer = this.getPayer(relayRequest);
        uint256 ethMaxCharge = relayHub.calculateCharge(maxPossibleGas, relayRequest.relayData);
        ethMaxCharge += relayRequest.request.value;
        tokenPreCharge = _getAmountIn(uniswap, token, ethMaxCharge);
    }

    // function _verifyPaymasterData(GsnTypes.RelayRequest calldata relayRequest) internal pure {
    //     // solhint-disable-next-line reason-string
    //     require(relayRequest.relayData.paymasterData.length == 32, "paymasterData: invalid length for Uniswap v1 exchange address");
    // }

    function preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    )
    external override virtual
    returns (bytes memory context, bool revertOnRecipientRevert) {
        (signature, approvalData);

        (IERC20 token, IUniswapV2Router02 uniswap) = _getToken(relayRequest.relayData.paymasterData);
        (address payer, uint256 tokenPrecharge) = _calculatePreCharge(token, uniswap, relayRequest, maxPossibleGas);
        token.transferFrom(payer, address(this), tokenPrecharge);
        return (abi.encode(payer, tokenPrecharge, token, uniswap, relayRequest.request.from), false);
    }

    function postRelayedCall(
        bytes calldata context,
        bool success,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData
    )
    external override virtual
    {
        (address payer, uint256 tokenPrecharge, IERC20 token, IUniswapV2Router02 uniswap, address from) = abi.decode(context, (address, uint256, IERC20, IUniswapV2Router02, address));
        _postRelayedCallInternal(success, payer, tokenPrecharge, 0, gasUseWithoutPost, relayData, token, uniswap, from);
    }

    function _postRelayedCallInternal(
        bool success,
        address payer,
        uint256 tokenPrecharge,
        uint256 valueRequested,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData,
        IERC20 token,
        IUniswapV2Router02 uniswap,
        address from
    ) internal {
        uint256 ethActualCharge = relayHub.calculateCharge(gasUseWithoutPost + gasUsedByPost, relayData);
        uint256 tokenActualCharge = _getAmountIn(uniswap, token, valueRequested + ethActualCharge); //uniswap.getTokenToEthOutputPrice(valueRequested + ethActualCharge);
        uint256 tokenRefund = tokenPrecharge - tokenActualCharge;
        if(success){
            IArbitrager(payer).cutGsnGas(from, address(token), tokenActualCharge);
        }
        _refundPayer(payer, token, tokenRefund);
        _depositProceedsToHub(ethActualCharge, tokenActualCharge, uniswap, token);

        // emit TokensCharged(gasUseWithoutPost, gasUsedByPost, ethActualCharge, tokenActualCharge);
    }

    function _refundPayer(
        address payer,
        IERC20 token,
        uint256 tokenRefund
    ) private {
        require(token.transfer(payer, tokenRefund), "failed refund");
    }

    function _depositProceedsToHub(uint256 ethActualCharge, uint256 tokenActualCharge, IUniswapV2Router02 uniswap, IERC20 token) private {
        //solhint-disable-next-line
        if(address(token) == address(weth)) {
            weth.withdraw(ethActualCharge);
        } else {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (address(token), address(weth));
            token.approve(address(uniswap), tokenActualCharge);
            uniswap.swapTokensForExactETH(ethActualCharge, tokenActualCharge, path, address(this), block.timestamp+60*15);
        }
        //uniswap.tokenToEthSwapOutput(ethActualCharge, type(uint256).max, block.timestamp+60*15);
        relayHub.depositFor{value:ethActualCharge}(address(this));
    }

    function depositEthToHub() external payable{
        relayHub.depositFor{value:msg.value}(address(this));
    }

    event TokensCharged(uint256 gasUseWithoutPost, uint256 gasJustPost, uint256 ethActualCharge, uint256 tokenActualCharge);
}