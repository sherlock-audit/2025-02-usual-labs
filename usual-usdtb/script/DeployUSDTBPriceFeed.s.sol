// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { NAVProxyUSDTBPriceFeed } from "../src/oracle/NAVProxyUSDTBPriceFeed.sol";

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

contract DeployUSDTBPriceFeedScript is Script {
    IPyth public pyth;
    bytes32 public usdtbPriceId;

    address internal constant _PYTH_MAINNET_ORACLE = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 internal constant _USDTB_PRICE_ID = 0x967549f1ff4869f41cb354a7116b9e5a9a3091bebe0b2640eeed745ca1f7f90b;

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        pyth = IPyth(_PYTH_MAINNET_ORACLE);
        usdtbPriceId = _USDTB_PRICE_ID;

        console2.log("Deployer:", deployer_);

        vm.startBroadcast(deployer_);

        address priceFeed = address(new NAVProxyUSDTBPriceFeed(address(pyth), usdtbPriceId));

        vm.stopBroadcast();

        console2.log("price feed:", priceFeed);
    }
}
