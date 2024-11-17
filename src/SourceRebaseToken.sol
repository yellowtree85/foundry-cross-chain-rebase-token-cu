// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@ccip/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

contract RebaseToken is RebaseTokenBase {
    address public s_vault;

    event VaultAndPoolSet(address vault, address pool);

    constructor() RebaseTokenBase() {}

    modifier onlyPoolOrVault() {
        if (msg.sender != s_pool && msg.sender != s_vault) {
            revert RebaseToken__SenderNotPoolOrVault(msg.sender);
        }
        _;
    }

    function setVaultAndPool(address vault, address pool) external onlyOwner {
        s_vault = vault;
        s_pool = pool;
        emit VaultAndPoolSet(vault, pool);
    }
}
