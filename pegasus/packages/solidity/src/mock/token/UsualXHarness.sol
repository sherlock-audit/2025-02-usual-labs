//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {UsualX} from "src/vaults/UsualX.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USUAL,
    MAX_25_PERCENT_WITHDRAW_FEE
} from "src/constants.sol";

import {NullContract, AmountTooBig} from "src/errors.sol";

contract UsualXHarness is UsualX {
    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the UsualX contract.
    /// @param _registryContract The address of the RegistryContract.
    /// @param _withdrawFeeBps The withdrawal fee in basis points.
    /// @param _name The name of the token.
    /// @param _symbol The symbol of the token.
    function initialize(
        address _registryContract,
        uint256 _withdrawFeeBps,
        string memory _name,
        string memory _symbol
    ) external initializer {
        if (_registryContract == address(0)) {
            revert NullContract();
        }
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryContract = IRegistryContract(_registryContract);
        address _underlyingToken = $.registryContract.getContract(CONTRACT_USUAL);
        __YieldBearingVault_init(_underlyingToken, _name, _symbol);
        __Pausable_init_unchained();
        __ReentrancyGuard_init();
        __EIP712_init_unchained(_name, "1");

        if (_withdrawFeeBps > MAX_25_PERCENT_WITHDRAW_FEE) {
            revert AmountTooBig();
        }
        $.withdrawFeeBps = _withdrawFeeBps;
        $.registryAccess = IRegistryAccess(
            IRegistryContract(_registryContract).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }
}
