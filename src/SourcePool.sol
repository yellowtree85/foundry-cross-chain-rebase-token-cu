// SPDX-License-Identifier: BUSL-1.1
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

    function _burn(address account, uint256 amount) internal virtual {
        IRebaseToken(address(i_token)).burn(account, amount);
    }

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory)
    {
        _validateLockOrBurn(lockOrBurnIn);

        address receiver = abi.decode(lockOrBurnIn.receiver, (address));
        uint256 amount = lockOrBurnIn.amount;

        _burn(receiver, amount);

        // NOTE: convert to underlying and bridge the corresponding eligible/pending amounts (if applicable)

        // get the necessary info
        (uint256 newUserIndex, uint256 currentAccumulatedRate, uint256 lastTimestamp) =
            IRebaseToken(address(i_token)).getUserInfo(receiver);

        // encode a function call to pass the caller's info to the destination pool and update it
        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encodeWithSelector(
                IRebaseToken.setUserInfo.selector, receiver, newUserIndex, currentAccumulatedRate, lastTimestamp
            )
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
