// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";

import {
    MINIMUM_USDC_PROVIDED,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_ORACLE,
    CONTRACT_USD0,
    CONTRACT_USDC
} from "src/constants.sol";

import {NullContract} from "src/errors.sol";

contract SwapperEngineHarness is SwapperEngine {
    /// @notice Constructor for initializing the contract.
    /// @dev This constructor is used to set the initial state of the contract.
    /// @param registryContract The registry contract address.
    function initialize(address registryContract) public initializer {
        if (registryContract == address(0)) {
            revert NullContract();
        }
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        $.registryContract = IRegistryContract(registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.usdcToken = IERC20($.registryContract.getContract(CONTRACT_USDC));
        $.usd0 = IERC20($.registryContract.getContract(CONTRACT_USD0));
        $.nextOrderId = 1;
        $.oracle = IOracle($.registryContract.getContract(CONTRACT_ORACLE));
        $.minimumUSDCAmountProvided = MINIMUM_USDC_PROVIDED;
    }
}
