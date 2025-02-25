// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";
import {DistributionModule} from "src/distribution/DistributionModule.sol";
import {Usd0} from "src/token/Usd0.sol";
import {UsualXHarness} from "src/mock/token/UsualXHarness.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {UsualSP} from "src/token/UsualSP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {
    CONTRACT_USD0PP,
    CONTRACT_USUALSP,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_USD0,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USUALX,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    CONTRACT_USUALS,
    RATE0,
    USUALSName,
    USUALSSymbol,
    USUALXName,
    USUALXSymbol,
    USUALX_WITHDRAW_FEE,
    VESTING_DURATION_THREE_YEARS,
    REGISTRY_CONTRACT_MAINNET,
    USUAL_MULTISIG_MAINNET,
    INITIAL_ACCUMULATED_FEES,
    INITIAL_SHARES_MINTING
} from "src/constants.sol";

import {console} from "forge-std/console.sol";
import {UpgradeScriptBase} from "scripts/deployment/utils/UpgradeScriptBase.sol";

contract P14 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // upgrade DaoCollateral fixes
        DeployImplementationAndLogs(
            "DaoCollateral.sol",
            CONTRACT_DAO_COLLATERAL,
            abi.encodeCall(DaoCollateral.initializeV2, ())
        );
        // Upgrade Usd0 using V2
        DeployImplementationAndLogs(
            "Usd0.sol", CONTRACT_USD0, abi.encodeCall(Usd0.initializeV2, ())
        );
        // AirDropTaxCollector
        DeployNewProxyWithImplementationAndLogsOrFail(
            "AirdropTaxCollector.sol",
            CONTRACT_AIRDROP_TAX_COLLECTOR,
            abi.encodeCall(AirdropTaxCollector.initialize, (address(RegistryContractProxy)))
        );
    }
}

contract P15 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }

        // AirDropDistribution
        DeployNewProxyWithImplementationAndLogsOrFail(
            "AirdropDistribution.sol",
            CONTRACT_AIRDROP_DISTRIBUTION,
            abi.encodeCall(AirdropDistribution.initialize, (address(RegistryContractProxy)))
        );
    }
}

contract P16 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // Upgrade UsualX using V2
        DeployImplementationAndLogs(
            "UsualX.sol",
            CONTRACT_USUALX,
            abi.encodeCall(UsualX.initializeV1, (INITIAL_ACCUMULATED_FEES, INITIAL_SHARES_MINTING))
        );
    }
}

contract P17 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // Upgrade Usd0++ using V2
        DeployImplementationAndLogs(
            "Usd0PP.sol", CONTRACT_USD0PP, abi.encodeCall(Usd0PP.initializeV2, ())
        );
    }
}
