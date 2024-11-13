// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract DestPool is TokenPool {
    error CallToTokenFailed();
    error NoReturnDataExpected();

    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router)
        TokenPool(token, allowlist, rmnProxy, router)
    {}

    /// @notice Burns the tokens on the destination chain
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn) external returns (Pool.LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        return
            Pool.LockOrBurnOutV1({destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector), destPoolData: ""});
    }

    /// @notice Mints the tokens on the source chain
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;
        // Mint rebasing tokens to the receiver on the destination chain (this also performs the base update logic in case there are already pending deposits that need to be made eligible, so do it before encoded call to setUserDepositInfo below)
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount);

        uint256 userIndex = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        // call the destination token contract to update the user index
        IRebaseToken(address(i_token)).setUserAccumulatedRate(receiver, userIndex);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
