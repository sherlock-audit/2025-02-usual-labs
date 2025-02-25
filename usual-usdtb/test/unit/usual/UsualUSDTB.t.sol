// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test, console2 } from "../../../lib/forge-std/src/Test.sol";
import { Pausable } from "../../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import { MockUSDTB, MockRegistryAccess } from "../../utils/Mocks.sol";

import {
    DEFAULT_ADMIN_ROLE,
    USUAL_USDTB_UNWRAP,
    USUAL_USDTB_PAUSE,
    USUAL_USDTB_UNPAUSE,
    BLACKLIST_ROLE,
    USUAL_USDTB_MINTCAP_ALLOCATOR
} from "../../../src/constants.sol";
import { UsualUSDTB } from "../../../src/usual/UsualUSDTB.sol";

import { IUsualUSDTB } from "../../../src/usual/interfaces/IUsualUSDTB.sol";

contract UsualUSDTBUnitTests is Test {
    address internal _treasury = makeAddr("treasury");

    address internal _admin = makeAddr("admin");
    address internal _pauser = makeAddr("pauser");
    address internal _unpauser = makeAddr("unpauser");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _other = makeAddr("other");

    address internal _blacklister = makeAddr("blacklister");

    address internal _mintCapAllocator = makeAddr("mintCapAllocator");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    MockUSDTB internal _usdtb;
    MockRegistryAccess internal _registryAccess;

    UsualUSDTB internal _usualUSDTB;

    event MintCapSet(uint256 newMintCap);

    function setUp() external {
        _usdtb = new MockUSDTB();
        _registryAccess = new MockRegistryAccess();

        // Set default admin role.
        _registryAccess.grantRole(DEFAULT_ADMIN_ROLE, _admin);

        _usualUSDTB = new UsualUSDTB();
        _resetInitializerImplementation(address(_usualUSDTB));
        _usualUSDTB.initialize(address(_usdtb), address(_registryAccess));

        // Set pauser/unpauser role.
        vm.prank(_admin);
        _registryAccess.grantRole(USUAL_USDTB_PAUSE, _pauser);
        vm.prank(_admin);
        _registryAccess.grantRole(USUAL_USDTB_UNPAUSE, _unpauser);

        // Grant BLACKLIST_ROLE to the blacklister instead of admin
        vm.prank(_admin);
        _registryAccess.grantRole(BLACKLIST_ROLE, _blacklister);

        // Fund accounts with USDTB tokens and allow them to unwrap.
        for (uint256 i = 0; i < _accounts.length; ++i) {
            _usdtb.setBalanceOf(_accounts[i], 10e18);

            vm.prank(_admin);
            _registryAccess.grantRole(USUAL_USDTB_UNWRAP, _accounts[i]);
        }

        // Add mint cap allocator role to a separate address
        vm.prank(_admin);
        _registryAccess.grantRole(USUAL_USDTB_MINTCAP_ALLOCATOR, _mintCapAllocator);

        // Set an initial mint cap
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(10_000e18);
    }

    /* ============ initialization ============ */
    function test_init() external view {
        assertEq(_usualUSDTB.usdtb(), address(_usdtb));
        assertEq(_usualUSDTB.registryAccess(), address(_registryAccess));
        assertEq(_usualUSDTB.name(), "UsualUSDTB");
        assertEq(_usualUSDTB.symbol(), "USUALUSDTB");
        assertEq(_usualUSDTB.decimals(), 18);
    }

    /* ============ wrap ============ */
    function test_wrap_wholeBalance() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        assertEq(_usdtb.balanceOf(_alice), 0);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 10e18);

        assertEq(_usualUSDTB.balanceOf(_alice), 10e18);
    }

    function test_wrap() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 5e18);

        assertEq(_usdtb.balanceOf(_alice), 5e18);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 5e18);

        assertEq(_usualUSDTB.balanceOf(_alice), 5e18);
    }

    function test_wrapWithPermit() external {
        vm.prank(_bob);
        _usualUSDTB.wrapWithPermit(_alice, 5e18, 0, 0, bytes32(0), bytes32(0));

        assertEq(_usdtb.balanceOf(_alice), 10e18);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 5e18);
        assertEq(_usualUSDTB.balanceOf(_alice), 5e18);

        assertEq(_usualUSDTB.balanceOf(_bob), 0);
        assertEq(_usdtb.balanceOf(_bob), 5e18);
    }

    function test_wrapWithPermit_invalidAmount() external {
        vm.expectRevert(IUsualUSDTB.InvalidAmount.selector);

        vm.prank(_bob);
        _usualUSDTB.wrapWithPermit(_alice, 0, 0, 0, bytes32(0), bytes32(0));
    }

    function test_wrap_exceedsMintCap() external {
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(5e18);

        vm.expectRevert(IUsualUSDTB.MintCapExceeded.selector);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);
    }

    function test_wrap_upToMintCap() external {
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(15e18);

        // First wrap should succeed
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        // Second wrap should succeed (within cap)
        vm.prank(_bob);
        _usualUSDTB.wrap(_bob, 5e18);

        // Third wrap should fail (exceeds cap)
        vm.expectRevert(IUsualUSDTB.MintCapExceeded.selector);

        vm.prank(_charlie);
        _usualUSDTB.wrap(_charlie, 1e18);
    }

    function test_wrap_invalidAmount() external {
        vm.expectRevert(IUsualUSDTB.InvalidAmount.selector);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 0);
    }

    function testFuzz_wrap_withMintCap(uint256 mintCap, uint256 wrapAmount) external {
        mintCap = bound(mintCap, 1e18, 1e22);
        wrapAmount = bound(wrapAmount, 1, mintCap);

        vm.assume(mintCap != _usualUSDTB.mintCap());

        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(mintCap);

        _usdtb.setBalanceOf(_alice, wrapAmount);

        // Wrap tokens up to the mint cap
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, wrapAmount);

        // Check that the total supply does not exceed the mint cap
        assertLe(_usualUSDTB.totalSupply(), mintCap);

        // Check that the wrapped amount is correct
        assertEq(_usualUSDTB.balanceOf(_alice), wrapAmount);
    }

    /* ============ unwrap ============ */
    function test_unwrap() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_alice);
        _usualUSDTB.unwrap(_alice, 5e18);

        assertEq(_usdtb.balanceOf(_alice), 5e18);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 5e18);

        assertEq(_usualUSDTB.balanceOf(_alice), 5e18);
    }

    function test_unwrap_wholeBalance() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        assertEq(_usdtb.balanceOf(_alice), 0);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 10e18);
        assertEq(_usualUSDTB.balanceOf(_alice), 10e18);

        vm.prank(_alice);
        _usualUSDTB.unwrap(_alice, 10e18);

        assertEq(_usdtb.balanceOf(_alice), 10e18);
        assertEq(_usdtb.balanceOf(address(_usualUSDTB)), 0);

        assertEq(_usualUSDTB.balanceOf(_alice), 0);
    }

    function test_unwarp_notAllowed() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.unwrap(_other, 5e18);
    }

    function test_unwrap_invalidAmount() external {
        vm.expectRevert(IUsualUSDTB.InvalidAmount.selector);

        vm.prank(_alice);
        _usualUSDTB.unwrap(_alice, 0);
    }

    /* ============ pause ============ */
    function test_pause_wrap() external {
        vm.prank(_pauser);
        _usualUSDTB.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);
    }

    function test_pause_transfer() external {
        vm.prank(_pauser);
        _usualUSDTB.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);

        vm.prank(_alice);
        _usualUSDTB.transfer(_bob, 5e18);
    }

    function test_pause_unwrap() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_pauser);
        _usualUSDTB.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);

        vm.prank(_alice);
        _usualUSDTB.unwrap(_bob, 10e18);
    }

    function test_pause_unauthorized() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.pause();
    }

    function test_unpause_unauthorized() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.unpause();
    }

    /* ============ blacklist ============ */
    function test_blacklisted_wrap() external {
        assertEq(_usualUSDTB.isBlacklisted(_alice), false);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);

        assertEq(_usualUSDTB.isBlacklisted(_alice), true);

        vm.expectRevert(IUsualUSDTB.Blacklisted.selector);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);
    }

    function test_blacklisted_unwrap() external {
        assertEq(_usualUSDTB.isBlacklisted(_alice), false);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);

        assertEq(_usualUSDTB.isBlacklisted(_alice), true);

        vm.expectRevert(IUsualUSDTB.Blacklisted.selector);

        vm.prank(_alice);
        _usualUSDTB.unwrap(_alice, 10e18);
    }

    function test_blacklisted_transfer_sender() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);

        vm.expectRevert(IUsualUSDTB.Blacklisted.selector);

        vm.prank(_alice);
        _usualUSDTB.transfer(_bob, 10e18);
    }

    function test_blacklisted_transfer_receiver() external {
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_bob);

        vm.expectRevert(IUsualUSDTB.Blacklisted.selector);

        vm.prank(_alice);
        _usualUSDTB.transfer(_bob, 10e18);
    }

    function test_blacklist_unauthorized() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.blacklist(_alice);
    }

    function test_unBlacklist_unauthorized() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.unBlacklist(_alice);
    }

    function test_blacklist_unBlacklist() external {
        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);

        assertEq(_usualUSDTB.isBlacklisted(_alice), true);

        vm.expectRevert(IUsualUSDTB.Blacklisted.selector);

        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        vm.prank(_blacklister);
        _usualUSDTB.unBlacklist(_alice);

        vm.prank(_alice);
        uint256 res = _usualUSDTB.wrap(_alice, 10e18);
        assertEq(res, 10e18);

        assertEq(_usualUSDTB.isBlacklisted(_alice), false);
    }

    function test_blacklist_zeroAddress() external {
        vm.expectRevert(IUsualUSDTB.ZeroAddress.selector);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(address(0));
    }

    function test_unBlacklist_zeroAddress() external {
        vm.expectRevert(IUsualUSDTB.ZeroAddress.selector);

        vm.prank(_blacklister);
        _usualUSDTB.unBlacklist(address(0));
    }

    function test_blacklist_sameValue() external {
        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);

        vm.expectRevert(IUsualUSDTB.SameValue.selector);

        vm.prank(_blacklister);
        _usualUSDTB.blacklist(_alice);
    }

    function test_unBlacklist_sameValue() external {
        vm.expectRevert(IUsualUSDTB.SameValue.selector);

        vm.prank(_blacklister);
        _usualUSDTB.unBlacklist(_alice);
    }

    /* ============ mint cap ============ */
    function test_setMintCap() external {
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(100e18);

        assertEq(_usualUSDTB.mintCap(), 100e18);
    }

    function test_setMintCap_unauthorized() external {
        vm.expectRevert(IUsualUSDTB.NotAuthorized.selector);

        vm.prank(_other);
        _usualUSDTB.setMintCap(100e18);
    }

    function test_setMintCap_sameValue() external {
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(100e18);

        vm.expectRevert(IUsualUSDTB.SameValue.selector);

        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(100e18);
    }

    function test_setMintCap_uint96() external {
        vm.expectRevert(IUsualUSDTB.InvalidUInt96.selector);

        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(2 ** 96);
    }

    function test_setMintCap_emitsEvent() external {
        vm.expectEmit(false, false, false, true);
        emit MintCapSet(100e18);

        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(100e18);
    }

    /* ============ wrappable amount ============ */
    function test_getWrappableAmount() external {
        vm.prank(_mintCapAllocator);
        _usualUSDTB.setMintCap(100e18);

        // Initially, wrappable amount should be the full mint cap
        assertEq(_usualUSDTB.getWrappableAmount(100e18), 100e18);

        // Wrap some tokens
        vm.prank(_alice);
        _usualUSDTB.wrap(_alice, 10e18);

        // Check wrappable amount with amount exceeding difference between mint cap and total supply
        assertEq(_usualUSDTB.getWrappableAmount(100e18), 90e18);

        // Check wrappable amount with amount less than difference between mint cap and total supply
        assertEq(_usualUSDTB.getWrappableAmount(20e18), 20e18);
    }

    /* ============ utils ============ */
    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
    }
}
