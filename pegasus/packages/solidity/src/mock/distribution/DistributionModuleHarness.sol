// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DistributionModule} from "src/distribution/DistributionModule.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {IUsualSP} from "src/interfaces/token/IUsualSP.sol";
import {IUsualX} from "src/interfaces/vaults/IUsualX.sol";
import {IDaoCollateral} from "src/interfaces/IDaoCollateral.sol";
import {
    LBT_DISTRIBUTION_SHARE,
    LYT_DISTRIBUTION_SHARE,
    IYT_DISTRIBUTION_SHARE,
    BRIBE_DISTRIBUTION_SHARE,
    ECO_DISTRIBUTION_SHARE,
    DAO_DISTRIBUTION_SHARE,
    MARKET_MAKERS_DISTRIBUTION_SHARE,
    USUALX_DISTRIBUTION_SHARE,
    USUALSTAR_DISTRIBUTION_SHARE,
    INITIAL_BASE_GAMMA,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USD0PP,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    CONTRACT_USUALSP,
    CONTRACT_DAO_COLLATERAL
} from "src/constants.sol";
import {InvalidInput, NullContract} from "src/errors.sol";

contract DistributionModuleHarness is DistributionModule {
    /// @notice Initializes the contract
    /// @param _registryContract Address of the registry contract
    /// @param rate0 Initial rate0 value
    function initialize(IRegistryContract _registryContract, uint256 rate0) public initializer {
        if (address(_registryContract) == address(0)) {
            revert NullContract();
        }
        if (rate0 == 0) {
            revert InvalidInput();
        }

        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        $.registryContract = _registryContract;
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));

        $.usual = IUsual($.registryContract.getContract(CONTRACT_USUAL));
        $.usd0PP = IERC20Metadata($.registryContract.getContract(CONTRACT_USD0PP));
        $.daoCollateral = IDaoCollateral($.registryContract.getContract(CONTRACT_DAO_COLLATERAL));
        $.usualSP = IUsualSP($.registryContract.getContract(CONTRACT_USUALSP));
        $.usualX = IUsualX($.registryContract.getContract(CONTRACT_USUALX));

        // Initialize parameters (scaled values in basis points)
        $.lbtDistributionShare = LBT_DISTRIBUTION_SHARE;
        $.lytDistributionShare = LYT_DISTRIBUTION_SHARE;
        $.iytDistributionShare = IYT_DISTRIBUTION_SHARE;
        $.bribeDistributionShare = BRIBE_DISTRIBUTION_SHARE;
        $.ecoDistributionShare = ECO_DISTRIBUTION_SHARE;
        $.daoDistributionShare = DAO_DISTRIBUTION_SHARE;
        $.marketMakersDistributionShare = MARKET_MAKERS_DISTRIBUTION_SHARE;
        $.usualXDistributionShare = USUALX_DISTRIBUTION_SHARE;
        $.usualStarDistributionShare = USUALSTAR_DISTRIBUTION_SHARE;
        $.d = 2500; // 25% in basis point precision
        $.m0 = 10.21e18; // initial supply factor
        $.rateMin = 50; // 0.5% in basis point precision
        $.baseGamma = INITIAL_BASE_GAMMA; // % in basis points precision

        // Memoize initial values (immutable)
        $.initialSupplyPp0 = $.usd0PP.totalSupply();
        $.p0 = _getUSD0Price($);
        $.rate0 = rate0;
    }
}
