// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {USD0_BURN, USD0_MINT, USD0PP_MINT, USD0PP_BURN} from "src/constants.sol";

address constant REGISTRY_ACCESS_ARBITRUM = 0x168BA269fc6CDe6115F3b03C94F55831165D374F;
address constant USD0_ADAPTER_ARBITRUM = 0xE14C486b93C3B62F76F88cf8FE4B36fb672f3B26;
address constant USD0PP_ADAPTER_ARBITRUM = 0xd155d91009cbE9B0204B06CE1b62bf1D793d3111;
address constant usualArbAdmin = 0x192482bdB33B670ac7dA705cEF9E98C93abeEc9a;

contract GrantAdapterRolesArbitrumScript is Script {
    RegistryAccess public registryAccess_;

    function run() public {
        if (block.chainid != 42_161) {
            revert("This script is intended to run on Arbitrum mainnet only");
        }
        registryAccess_ = RegistryAccess(REGISTRY_ACCESS_ARBITRUM);

        vm.startBroadcast();

        console.log("Granting roles to USD0 OFTMintAndBurnAdapter on Arbitrum");
        grantRole(USD0_ADAPTER_ARBITRUM, USD0_MINT);
        grantRole(USD0_ADAPTER_ARBITRUM, USD0_BURN);

        console.log("Granting roles to USD0PP OFTMintAndBurnAdapter on Arbitrum");
        grantRole(USD0PP_ADAPTER_ARBITRUM, USD0PP_MINT);
        grantRole(USD0PP_ADAPTER_ARBITRUM, USD0PP_BURN);

        registryAccess_.beginDefaultAdminTransfer(usualArbAdmin);

        (address pendingAdmin, uint256 schedule) = registryAccess_.pendingDefaultAdmin();
        require(pendingAdmin == usualArbAdmin, "Pending admin not set correctly");
        console.log(
            "Default admin transfer initiated. Pending admin:", pendingAdmin, "Schedule:", schedule
        );

        vm.stopBroadcast();

        console.log("Roles granted successfully");
    }

    function grantRole(address adapter, bytes32 role) internal {
        registryAccess_.grantRole(role, adapter);

        require(registryAccess_.hasRole(role, adapter), "Role not granted");

        console.log("Role granted and verified for adapter:", adapter);
        console.logBytes32(role);
    }
}

interface ISetRateLimiter {
    function setRateLimits(RateLimitConfig[] memory _rateLimitConfigs) external;
    function owner() external view returns (address);
}

struct RateLimitConfig {
    uint32 dstEid;
    uint256 limit;
    uint256 window;
}

contract SetRateLimitArbitrumMainnetScript is Script {
    function run() public {
        if (block.chainid != 42_161 && block.chainid != 1) {
            revert("This script is intended to run on Arbitrum One or Ethereum mainnet only");
        }

        RateLimitConfig[] memory config = new RateLimitConfig[](1);
        // Below are copy pasted valued from Telegram to a decoder to this script
        config[0] = RateLimitConfig(30_101, 1_000_000_000_000_000_000_000, 3600);
        if (block.chainid == 42_161) {
            config[0].dstEid = 30_101;
        } else {
            // chainid == 1
            config[0].dstEid = 30_110;
        }
        address owner = ISetRateLimiter(USD0PP_ADAPTER_ARBITRUM).owner();
        vm.startBroadcast();
        require(msg.sender != owner, "Only the owner can call this function");
        ISetRateLimiter(USD0_ADAPTER_ARBITRUM).setRateLimits(config);
        ISetRateLimiter(USD0PP_ADAPTER_ARBITRUM).setRateLimits(config);
        vm.stopBroadcast();
    }
}
