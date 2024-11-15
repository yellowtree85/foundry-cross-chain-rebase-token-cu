// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IBurnMintERC20} from "@ccip/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract SourcePool is TokenPool {
    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router)
        TokenPool(token, allowlist, rmnProxy, router)
    {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory)
    {
        _validateLockOrBurn(lockOrBurnIn);

        address receiver = abi.decode(lockOrBurnIn.receiver, (address));
        uint256 amount = lockOrBurnIn.amount;

        // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)
        uint256 newUserAccumulatedRate = IRebaseToken(address(i_token)).burn(address(this), amount);

        // encode a function call to pass the caller's info to the destination pool and update it
        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(newUserAccumulatedRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        virtual
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        // Mint rebasing tokens to the receiver (which also updates their deposit info on the source chain)
        IBurnMintERC20(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
