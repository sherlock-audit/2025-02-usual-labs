// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {RegistryContract} from "src/registry/RegistryContract.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {Usd0} from "src/token/Usd0.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Usual} from "src/token/Usual.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {UsualSP} from "src/token/UsualSP.sol";
import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";
import {DistributionModule} from "src/distribution/DistributionModule.sol";
import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {DaoCollateralHarness} from "src/mock/daoCollateral/DaoCollateralHarness.sol";
import {Usd0Harness} from "src/mock/token/Usd0Harness.sol";
import {Usd0PPHarness} from "src/mock/token/Usd0PPHarness.sol";
import {UsualSHarness} from "src/mock/token/UsualSHarness.sol";
import {UsualXHarness} from "src/mock/token/UsualXHarness.sol";
import {SwapperEngineHarness} from "src/mock/SwapperEngine/SwapperEngineHarness.sol";
import {DistributionModuleHarness} from "src/mock/distribution/DistributionModuleHarness.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TenderlyTestnetSetup} from "scripts/deployment/TenderlyTestnetSetup.s.sol";

import {
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_DATA_PUBLISHER,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    CONTRACT_ORACLE,
    CONTRACT_ORACLE_USUAL,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_USD0PP,
    CONTRACT_USD0,
    CONTRACT_USDC,
    VESTING_DURATION_THREE_YEARS,
    USUALSP_VESTING_STARTING_DATE,
    CONTRACT_USUALS,
    CONTRACT_USUALSP,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    AIRDROP_INITIAL_START_TIME,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    USUALS_BURN,
    USUAL_BURN,
    USUAL_MINT,
    USUALSName,
    USUALSSymbol,
    USUALName,
    USUALSymbol,
    AIRDROP_INITIAL_START_TIME,
    RATE0,
    USUALSSymbol,
    USUALX_WITHDRAW_FEE,
    USUALXName,
    USUALXSymbol,
    USUAL_MULTISIG_MAINNET,
    REGISTRY_CONTRACT_MAINNET,
    USUAL_PROXY_ADMIN_MAINNET,
    DISTRIBUTION_OPERATOR_ROLE,
    INITIAL_ACCUMULATED_FEES,
    INITIAL_SHARES_MINTING,
    AIRDROP_OPERATOR_ROLE,
    AIRDROP_PENALTY_OPERATOR_ROLE,
    CONTRACT_YIELD_TREASURY
} from "src/constants.sol";
import {
    USD0Name,
    USD0Symbol,
    REGISTRY_SALT,
    REGISTRY_ACCESS_MAINNET,
    DETERMINISTIC_DEPLOYMENT_PROXY,
    REDEEM_FEE
} from "src/mock/constants.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";
import "forge-std/console.sol";

/// @title   MainnetForkScript contract
/// @notice  Used to deploy to mainnet fork so that we can keep the same addresses
///          we deploy all our contracts if they don't exist on mainnet or to use the deployed ones.

contract MainnetFork is BaseScript {
    TokenMapping public tokenMapping;
    DaoCollateral public daoCollateral;
    Usual public usualToken;
    UsualX public usualX;
    Usd0PP public usd0PP;
    UsualSHarness public usualS;
    UsualSP public usualSP;
    SwapperEngine public swapperEngine;
    ClassicalOracle public classicalOracle;
    AirdropDistribution public airdropDistribution;
    DistributionModule public distributionModule;
    AirdropTaxCollector public airdropTaxCollector;
    address public distributionOperator = 0x0D25Fd4eACB769AB639D28aA76CcaDa93d3c8E1A;

    function run() public virtual override {
        super.run();
        // Check that the script is running on the correct chain
        if (block.chainid != 1) {
            console.log("Invalid chain");
            return;
        }
        address proxyAdmin;
        address harness;
        address proxy;
        registryAccess = IRegistryAccess(REGISTRY_ACCESS_MAINNET);
        registryContract = RegistryContract(REGISTRY_CONTRACT_MAINNET);

        // Upgrade to harnesses
        // SwapperEngine

        vm.startBroadcast(USUAL_MULTISIG_MAINNET);
        registryContract.setContract(CONTRACT_YIELD_TREASURY, USUAL_MULTISIG_MAINNET);
        vm.stopBroadcast();
        proxy = registryContract.getContract(CONTRACT_SWAPPER_ENGINE);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new SwapperEngineHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), harness, "");
        vm.stopBroadcast();
        // Usd0
        proxy = registryContract.getContract(CONTRACT_USD0);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new Usd0Harness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(proxy), harness, abi.encodeCall(Usd0.initializeV2, ())
        );
        vm.stopBroadcast();
        // DaoCollateral
        proxy = registryContract.getContract(CONTRACT_DAO_COLLATERAL);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new DaoCollateralHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(proxy),
            harness,
            abi.encodeCall(DaoCollateral.initializeV2, ())
        );
        vm.stopBroadcast();
        // Usd0PP
        proxy = registryContract.getContract(CONTRACT_USD0PP);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new Usd0PPHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(proxy), harness, abi.encodeCall(Usd0PP.initializeV2, ())
        );
        vm.stopBroadcast();
        address UsualXProxyAdmin = Upgrades.getAdminAddress(address(usualX));
        // Upgrade using V2
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        address UsualXImplementation = address(new UsualXHarness());
        // Upgrades as the ProxyAdmin contract
        ProxyAdmin(UsualXProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usualX)),
            UsualXImplementation,
            abi.encodeCall(UsualX.initializeV1, (INITIAL_ACCUMULATED_FEES, INITIAL_SHARES_MINTING))
        );
        vm.stopBroadcast();
        UsualXImplementation = Upgrades.getImplementationAddress(address(usualX));
        // UsualS
        proxy = registryContract.getContract(CONTRACT_USUALS);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new UsualSHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), harness, "");
        vm.stopBroadcast();
        // UsualX
        proxy = registryContract.getContract(CONTRACT_USUALX);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new UsualXHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(proxy),
            harness,
            abi.encodeCall(UsualX.initializeV1, (INITIAL_ACCUMULATED_FEES, INITIAL_SHARES_MINTING))
        );
        vm.stopBroadcast();
        // DistributionModule
        proxy = registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE);
        proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast(USUAL_PROXY_ADMIN_MAINNET);
        harness = address(new DistributionModuleHarness());
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), harness, "");
        vm.stopBroadcast();

        try registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR) {
            airdropTaxCollector =
                AirdropTaxCollector(registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));
        } catch {
            vm.startBroadcast(USUAL_MULTISIG_MAINNET);
            airdropTaxCollector = AirdropTaxCollector(
                Upgrades.deployTransparentProxy(
                    "AirdropTaxCollector.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(AirdropTaxCollector.initialize, (address(registryContract)))
                )
            );

            registryContract.setContract(
                CONTRACT_AIRDROP_TAX_COLLECTOR, address(airdropTaxCollector)
            );
            vm.stopBroadcast();
        }
        try registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION) {
            airdropDistribution =
                AirdropDistribution(registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION));
        } catch {
            vm.startBroadcast(USUAL_MULTISIG_MAINNET);
            airdropDistribution = AirdropDistribution(
                Upgrades.deployTransparentProxy(
                    "AirdropDistribution.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(AirdropDistribution.initialize, (address(registryContract)))
                )
            );

            registryContract.setContract(
                CONTRACT_AIRDROP_DISTRIBUTION, address(airdropDistribution)
            );
            vm.stopBroadcast();
        }
        // set roles
        vm.startBroadcast(USUAL_MULTISIG_MAINNET);
        registryAccess.grantRole(
            USUAL_MINT, registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION)
        );
        registryAccess.grantRole(USUAL_BURN, registryContract.getContract(CONTRACT_USUALX));
        registryAccess.grantRole(USUAL_BURN, registryContract.getContract(CONTRACT_USD0PP)); // After USD0++ upgrade

        registryAccess.grantRole(AIRDROP_OPERATOR_ROLE, 0xFCa95E89535E628c0f2d03a5F0b5d7aDC16FBb32);
        registryAccess.grantRole(
            AIRDROP_PENALTY_OPERATOR_ROLE, 0xFCa95E89535E628c0f2d03a5F0b5d7aDC16FBb32
        );

        registryAccess.grantRole(USUALS_BURN, USUAL_MULTISIG_MAINNET);
        registryAccess.grantRole(USUAL_BURN, USUAL_MULTISIG_MAINNET);
        registryAccess.grantRole(USUAL_MINT, USUAL_MULTISIG_MAINNET);
        vm.stopBroadcast();
    }
}
