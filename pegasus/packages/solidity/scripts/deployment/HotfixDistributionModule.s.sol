// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {CONTRACT_DISTRIBUTION_MODULE, REGISTRY_CONTRACT_MAINNET} from "src/constants.sol";

import {console} from "forge-std/console.sol";
import {UpgradeScriptBase} from "scripts/deployment/utils/UpgradeScriptBase.sol";

contract HotfixDistributionModule is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // upgrade SwapperEngine fixes
        DeployImplementationAndLogs("DistributionModule.sol", CONTRACT_DISTRIBUTION_MODULE, "");
    }
}
