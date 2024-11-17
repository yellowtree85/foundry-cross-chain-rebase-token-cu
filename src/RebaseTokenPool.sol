// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    error Pool__NotSourceChain();

    event Deposit(address indexed user, uint256 amount, uint256 userInterestRate);
    event Redeem(address indexed user, uint256 amount);

    uint256 public immutable i_sourceChainId;

    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router, uint256 _sourceChainId)
        TokenPool(token, allowlist, rmnProxy, router)
    {
        sourceChainId = _sourceChainId;
    }

    receive() external payable {}

    modifier onlySourceChain() {
        if (block.chainid != i_sourceChainId) revert Pool__NotSourceChain();
        _;
    }

    function deposit() external payable onlySourceChain {
        // 1. checks and 2. effects are performed in here
        i_token.mint(msg.sender, msg.value, s_interestRate);
        emit Deposit(msg.sender, msg.value, s_interestRate);
    }

    /**
     * @dev redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external onlySourceChain {
        // 1. Checks and effects are performed in herre
        i_token.burn(msg.sender, _amount);

        // executes redeem of the underlying asset
        // NOTE: Implement on the vault contract
        // updateAccumulatedRate(); // NOTE: surely this only needs to be called if interestRate changes? otherwise it's just linear with time anyway?
        payable(msg.sender).transfer(_amount);
        //vault.redeem(msg.sender, amountToRedeem);
        emit Redeem(msg.sender, _amount);
    }

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory)
    {
        _validateLockOrBurn(lockOrBurnIn);

        // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)
        uint256 currentInterestRate = IRebaseToken(address(i_token)).getInterestRate();
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // encode a function call to pass the caller's info to the destination pool and update it
        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(currentInterestRate)
        });
    }

    /// @notice Mints the tokens on the source chain
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        // Mint rebasing tokens to the receiver on the destination chain
        // This will also mint any interest that has accrued since the last time the user's balance was updated.
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount);
        // This needs to be set after otherwise any pending interst that has not yet been minted will be lost.
        IRebaseToken(address(i_token)).setUserInterestRate(receiver, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
