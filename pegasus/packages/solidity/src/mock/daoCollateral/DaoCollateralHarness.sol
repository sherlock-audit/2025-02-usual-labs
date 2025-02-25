// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";

import {
    MAX_REDEEM_FEE,
    CONTRACT_USD0,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_ORACLE,
    CONTRACT_TREASURY
} from "src/constants.sol";

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {ITokenMapping} from "src/interfaces/tokenManager/ITokenMapping.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";

import {RedeemFeeTooBig, NullContract} from "src/errors.sol";

contract DaoCollateralHarness is DaoCollateral {
    /// @notice Initializes the DaoCollateral contract with registry information and initial configuration.
    /// @param _registryContract The address of the registry contract.
    /// @param _redeemFee The initial redeem fee, in basis points.
    function initialize(address _registryContract, uint256 _redeemFee) public initializer {
        // can't have a redeem fee greater than 25%
        if (_redeemFee > MAX_REDEEM_FEE) {
            revert RedeemFeeTooBig();
        }

        if (_registryContract == address(0)) {
            revert NullContract();
        }

        __EIP712_init_unchained("DaoCollateral", "1");
        __Nonces_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.redeemFee = _redeemFee;

        IRegistryContract registryContract = IRegistryContract(_registryContract);
        $.registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));

        $.treasury = address(registryContract.getContract(CONTRACT_TREASURY));
        $.tokenMapping = ITokenMapping(registryContract.getContract(CONTRACT_TOKEN_MAPPING));
        $.usd0 = IUsd0(registryContract.getContract(CONTRACT_USD0));

        $.oracle = IOracle(registryContract.getContract(CONTRACT_ORACLE));

        $.swapperEngine = ISwapperEngine(registryContract.getContract(CONTRACT_SWAPPER_ENGINE));
    }

    /// @notice Initializes the DaoCollateral contract with registry information and update configuration.
    /// @param _registryContract The address of the registry contract.
    /* cspell:disable-next-line */
    function initializeV1(address _registryContract) public reinitializer(2) {
        if (_registryContract == address(0)) {
            revert NullContract();
        }

        __EIP712_init_unchained("DaoCollateral", "1");
        __Nonces_init_unchained();

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryContract = IRegistryContract(_registryContract);
        $.swapperEngine = ISwapperEngine(
            IRegistryContract(_registryContract).getContract(CONTRACT_SWAPPER_ENGINE)
        );
    }
}
