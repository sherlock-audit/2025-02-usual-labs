// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console2 } from "../../../lib/forge-std/src/Test.sol";
import { Vm } from "../../../lib/forge-std/src/Vm.sol";

import { ProxyAdmin } from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "../../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { UsualUSDTB } from "../../../src/usual/UsualUSDTB.sol";

import { TestBase } from "./TestBase.sol";

// Required for testing UsualUSDTB upgradeability
contract V2 {
    function initializeV2Test() public {}

    function version() public pure returns (uint256) {
        return 2;
    }
}

contract UsualUSDTBV2 is UsualUSDTB, V2 {}

contract UsualUSDTBIntegrationTests is TestBase {
    function setUp() external {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        _deployComponents();
        _fundAccounts();
        _grantRoles();

        // Set Mint Cap
        vm.prank(_admin);
        _usualUSDTB.setMintCap(10_000e18);
    }

    function test_integration_constants() external view {
        assertEq(_usualUSDTB.name(), "UsualUSDTB");
        assertEq(_usualUSDTB.symbol(), "USUALUSDTB");
        assertEq(_usualUSDTB.decimals(), 18);
    }                 

    function test_wrapWithPermits() external {
        assertEq(_usdtb.balanceOf(_alice), 10e18);

        _wrapWithPermitVRS(_alice, _aliceKey, _alice, 5e18, 0, block.timestamp);

        assertEq(_usualUSDTB.balanceOf(_alice), 5e18);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 5e18);

        _wrapWithPermitVRS(_alice, _aliceKey, _alice, 5e18, 1, block.timestamp);

        assertEq(_usualUSDTB.balanceOf(_alice), 10e18);
        assertEq(_usdtb.balanceOf(_alice), 0);
    }

    function test_upgrade() external {
        address usualUSDTBV2 = address(new UsualUSDTBV2());

        address proxyAdmin = _getAdminAddress(address(_usualUSDTB));

        vm.prank(_admin);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(_usualUSDTB)),
            usualUSDTBV2,
            abi.encodeWithSelector(V2.initializeV2Test.selector)
        );

        assertEq(V2(address(_usualUSDTB)).version(), 2);
    }

    function _getAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
