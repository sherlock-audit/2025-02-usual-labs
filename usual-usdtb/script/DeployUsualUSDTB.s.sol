// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { UsualUSDTB } from "../src/usual/UsualUSDTB.sol";

import {
    TransparentUpgradeableProxy
} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployUsualUSDTBScript is Script {
    address internal constant _USDTB_TOKEN = 0xC139190F447e929f090Edeb554D95AbB8b18aC1C; // Mainnet USDTB

    address internal constant _USUAL_REGISTRY_ACCESS = 0x0D374775E962c3608B8F0A4b8B10567DF739bb56; // Usual registry access

    address internal constant _USUAL_ADMIN = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7; // Usual default admin

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console2.log("Deployer:", deployer_);

        vm.startBroadcast(deployer_);

        address usualUSDTBImplementation = address(new UsualUSDTB());
        bytes memory usualUSDTBData = abi.encodeWithSignature(
            "initialize(address,address)",
            _USDTB_TOKEN,
            _USUAL_REGISTRY_ACCESS
        );
        address usualUSDTB = address(new TransparentUpgradeableProxy(usualUSDTBImplementation, _USUAL_ADMIN, usualUSDTBData));

        vm.stopBroadcast();

        console2.log("UsualUSDTB implementation:", usualUSDTBImplementation);
        console2.log("UsualUSDTB:", usualUSDTB);
    }
}
