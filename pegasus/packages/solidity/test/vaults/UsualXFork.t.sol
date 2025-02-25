// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {ONE_MONTH_IN_SECONDS} from "src/mock/constants.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {Usual} from "src/token/Usual.sol";
import {YIELD_PRECISION} from "src/constants.sol";
import {SetupTest} from "../setup.t.sol";
import {ERC165Checker} from "openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {
    NullContract,
    NullAddress,
    AmountTooBig,
    Blacklisted,
    SameValue,
    ZeroYieldAmount,
    StartTimeNotInFuture,
    EndTimeNotAfterStartTime,
    InsufficientAssetsForYield,
    CurrentTimeBeforePeriodFinish,
    StartTimeBeforePeriodFinish
} from "src/errors.sol";

import {
    BASIS_POINT_BASE,
    USUAL_MINT,
    REGISTRY_CONTRACT_MAINNET,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    BLACKLIST_ROLE,
    CONTRACT_DISTRIBUTION_MODULE,
    MAX_25_PERCENT_WITHDRAW_FEE,
    USUALSymbol,
    USUALName,
    USUALXSymbol,
    USUALXName,
    USUALX_WITHDRAW_FEE,
    INITIAL_ACCUMULATED_FEES,
    INITIAL_BURN_RATIO_BPS,
    INITIAL_SHARES_MINTING,
    USUALX_REDISTRIBUTION_CONTRACT
} from "src/constants.sol";
import "forge-std/console.sol";
import {ITransparentUpgradeableProxy} from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {UsualXHarness} from "src/mock/token/UsualXHarness.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UsualXFork is SetupTest, UsualX {
    using Math for uint256;

    UsualX usualXVault;
    address distributionModuleAddress;
    uint256 usualxBalanceBeforeUpgrade;

    function setUp() public override(SetupTest) {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);

        // NOTE: override set up to use mainnet addresses
        alice = 0x6c6A2b6b2b0d40E826BFde89Fe2e081ca408B042;
        bob = 0x6C6A2b6b2b0d40e826BfdE89fe2e081CA408b043;
        admin = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;

        // Get existing contracts from registry
        registryContract = RegistryContract(REGISTRY_CONTRACT_MAINNET);
        registryAccess = RegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        usualToken = Usual(registryContract.getContract(CONTRACT_USUAL));
        distributionModuleAddress = registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE);
        // Get existing UsualX proxy address
        UsualX usualXMainnet = UsualX(registryContract.getContract(CONTRACT_USUALX));
        address UsualXProxyAdminContract = Upgrades.getAdminAddress(address(usualXMainnet));
        Ownable proxy = Ownable(UsualXProxyAdminContract);
        address usualProxyAdminMainnet = proxy.owner();
        usualxBalanceBeforeUpgrade = usualToken.balanceOf(address(usualXMainnet));
        vm.startPrank(usualProxyAdminMainnet);

        console.log(
            "usualXHarness: ",
            address(usualXMainnet),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualXMainnet))
        );

        console.log(
            "usualXHarness: ",
            address(usualXMainnet),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualXMainnet))
        );

        vm.stopPrank();

        // Set the proxy as our usualXVault instance
        usualXVault = usualXMainnet;

        // Label addresses for better trace output
        vm.label(address(usualXVault), "UsualXVault");
        vm.label(address(usualToken), "UsualToken");
        vm.label(address(registryContract), "RegistryContract");
        vm.label(address(registryAccess), "RegistryAccess");

        // Setup initial ETH balance for alice
        vm.deal(alice, 1 ether);
    }

    function _createNewUsualX() internal returns (UsualXHarness) {
        uint256 accumulatedFees = 0;
        uint256 initialShares = INITIAL_SHARES_MINTING;

        vm.startPrank(address(admin));
        UsualXHarness newUsualX = new UsualXHarness();
        _resetInitializerImplementation(address(newUsualX));
        newUsualX.initialize(address(registryContract), 1000, "UsualX", "USX");

        registryAccess.grantRole(USUAL_MINT, admin);
        usualToken.mint(address(newUsualX), initialShares);
        registryAccess.revokeRole(USUAL_MINT, admin);

        newUsualX.initializeV1(accumulatedFees, initialShares);

        registryContract.setContract(CONTRACT_USUALX, address(newUsualX));
        registryAccess.grantRole(USUAL_MINT, admin);
        vm.stopPrank();

        return newUsualX;
    }

    function testDepositAfterDistributionFork() public {
        UsualXHarness newUsualX = _createNewUsualX();

        // we will deposit 1M usual tokens to the vault
        uint256 initialDeposit = 1_000_000e18;
        // we are going to yield 10M usual tokens before that (as in prod right now)
        uint256 yieldAmount = 10_000_000e18;
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.prank(admin);
        usualToken.mint(address(newUsualX), yieldAmount);
        // Warp to end of yield period
        uint256 initialTotalAssets = newUsualX.totalAssets();
        assertEq(initialTotalAssets, 10_000e18, "initialTotalAssets should be 0");
        uint256 initialTotalSupply = newUsualX.totalSupply();
        assertEq(initialTotalSupply, 10_000e18, "totalSupply should be 10000e18");
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 1 days;
        // distribute the yield
        vm.prank(distributionModuleAddress);
        newUsualX.startYieldDistribution(yieldAmount - 10_000e18, startTime, endTime);
        vm.warp(endTime + 1);
        // now empty vault ,  10M yield already distributed  to the vault and no shares
        assertEq(newUsualX.totalAssets(), yieldAmount);
        assertEq(newUsualX.totalSupply(), 10_000e18);
        // alice want to deposit 1M usual tokens to the vault
        vm.startPrank(alice);
        usualToken.approve(address(newUsualX), initialDeposit);
        newUsualX.deposit(initialDeposit, alice);
        vm.stopPrank();
        //  the total assets of the vault should be 11M usual tokens
        assertEq(
            newUsualX.totalAssets(), initialDeposit + yieldAmount, "Incorrect final total assets"
        );
        // some shares should be minted to alice
        assertGt(newUsualX.balanceOf(alice), 0, " some shares should be minted to alice");
    }

    function testDistributionDepositsAndRedeemAfterFork() public {
        UsualXHarness newUsualX = _createNewUsualX();

        // Initial setup
        vm.startPrank(admin);
        registryAccess.grantRole(USUAL_MINT, admin);
        usualToken.mint(alice, 10_000e18);
        usualToken.mint(address(newUsualX), 600_000e18);
        usualToken.mint(bob, 600_000e18);
        vm.stopPrank();

        // Warp to specific time
        vm.warp(1_734_519_600);

        // Verify initial state
        assertEq(newUsualX.totalAssets(), 10_000e18);
        assertEq(newUsualX.totalSupply(), INITIAL_SHARES_MINTING);
        assertEq(usualToken.balanceOf(address(newUsualX)), 610_000e18);

        // Start yield distribution
        vm.prank(distributionModuleAddress);
        newUsualX.startYieldDistribution(600_000e18, block.timestamp, block.timestamp + 1 days);

        // Skip 1 hour and verify accrued yield
        skip(3600);
        assertEq(newUsualX.totalAssets(), 600_000e18 / 24 + 10_000e18);

        // Alice deposits
        vm.startPrank(alice);
        usualToken.approve(address(newUsualX), 10_000e18);
        newUsualX.deposit(10_000e18, alice);
        vm.stopPrank();

        uint256 aliceShares = newUsualX.balanceOf(alice);
        assertGt(aliceShares, 0);

        // Skip another hour
        skip(3600);

        // Bob deposits
        vm.startPrank(bob);
        usualToken.approve(address(newUsualX), 600_000e18);
        newUsualX.deposit(600_000e18, bob);
        vm.stopPrank();

        uint256 bobShares = newUsualX.balanceOf(bob);
        assertGt(bobShares, 0);

        // Warp to end and verify final state
        vm.warp(block.timestamp + 22 hours);
        uint256 finalAssets = newUsualX.totalAssets();
        uint256 totalShares = newUsualX.totalSupply();

        // Bob redeems
        vm.startPrank(bob);
        newUsualX.redeem(bobShares, bob, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            usualToken.balanceOf(bob), (bobShares * finalAssets / totalShares) * 90 / 100, 1000
        );

        // Alice redeems
        vm.startPrank(alice);
        newUsualX.redeem(aliceShares, alice, alice);
        vm.stopPrank();

        assertEq(newUsualX.balanceOf(alice), 0);
        assertEq(usualToken.balanceOf(alice), (aliceShares * finalAssets / totalShares) * 90 / 100);

        // Verify remaining balance
        uint256 initialReward = newUsualX.previewRedeem(INITIAL_SHARES_MINTING);
        assertApproxEqAbs(
            usualToken.balanceOf(address(newUsualX)),
            initialReward / 90 * 100 + newUsualX.getAccumulatedFees(),
            1000
        );
    }

    function testEndToEndUsualX() public {
        UsualXHarness newUsualX = _createNewUsualX();
        uint256 initialDeposit = 200_000_000e18;
        _checkInitialState(newUsualX);

        // Setup initial balances and deposits
        _setupBalancesAndDeposits(newUsualX, initialDeposit);

        uint256 assetsAfterDeposit = newUsualX.totalAssets();
        assertEq(
            assetsAfterDeposit, 10_000e18 + initialDeposit * 2, "Incorrect assets after deposit"
        );

        // Warp forward in time
        vm.warp(block.timestamp + 1 days);

        uint256 assetsAfterDepositAndWarp = newUsualX.totalAssets();
        assertEq(
            assetsAfterDepositAndWarp,
            10_000e18 + initialDeposit * 2,
            "Incorrect assets after deposit and warp"
        );

        // Check user shares and withdrawals
        _checkUserSharesAndWithdrawals(newUsualX);

        // Bob redeems before distribution period starts
        _handleBobFirstRedeem(newUsualX);

        // Start and check distribution period
        uint256 endTime = _handleDistributionPeriod(newUsualX);

        // Handle Bob's second deposit
        uint256 bobUsualBalanceBefore = usualToken.balanceOf(address(bob));
        _handleBobSecondDeposit(newUsualX);

        // Warp to end and check final state
        vm.warp(endTime);
        _checkFinalState(newUsualX);

        // Handle final withdrawals and distributions
        _handleFinalWithdrawalsAndDistributions(newUsualX, bobUsualBalanceBefore);
    }

    function _checkInitialState(UsualXHarness newUsualX) private view {
        uint256 usualBalanceRedistributionDao =
            usualToken.balanceOf(address(USUALX_REDISTRIBUTION_CONTRACT));
        assertLt(
            usualBalanceRedistributionDao,
            usualxBalanceBeforeUpgrade - 10_000e18,
            "DAO Redistribution balance should not be 0"
        );

        assertGt(usualxBalanceBeforeUpgrade, 0, "Initial usual balance should not be 0");
        assertEq(newUsualX.totalAssets(), 10_000e18, "Initial total assets should be 0");
        assertEq(newUsualX.totalSupply(), 10_000e18, "Initial total supply should be 0");
        assertEq(newUsualX.getBurnRatio(), INITIAL_BURN_RATIO_BPS, "Initial burn ratio should be 0");
        assertEq(newUsualX.getYieldRate(), 0, "Initial yield rate should be 0");
        assertEq(newUsualX.withdrawFeeBps(), 1000, "Initial withdraw fee should be 10%, 1000bps");
    }

    function _setupBalancesAndDeposits(UsualXHarness newUsualX, uint256 initialDeposit) private {
        vm.startPrank(admin);
        registryAccess.grantRole(USUAL_MINT, admin);
        usualToken.mint(alice, initialDeposit);
        usualToken.mint(bob, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(newUsualX), initialDeposit);
        newUsualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usualToken.approve(address(newUsualX), initialDeposit);
        newUsualX.deposit(initialDeposit, bob);
        vm.stopPrank();
    }

    function _checkUserSharesAndWithdrawals(UsualXHarness newUsualX) private view {
        uint256 userInitialAssetDeposit = 200_000_000e18;
        uint256 userInitialSharesMint = 200_000_000e18;
        uint256 aliceShares = newUsualX.balanceOf(address(alice));
        uint256 bobShares = newUsualX.balanceOf(address(bob));

        assertEq(aliceShares, userInitialSharesMint, "Alice's shares should be 20000");
        assertEq(bobShares, userInitialSharesMint, "Bob's shares should be 20000");

        uint256 fee =
            Math.mulDiv(userInitialAssetDeposit, 1000, BASIS_POINT_BASE, Math.Rounding.Ceil);

        assertEq(
            newUsualX.maxWithdraw(address(alice)),
            userInitialAssetDeposit - fee,
            "Alice's max withdraw should be 18000"
        );
        assertEq(
            newUsualX.maxWithdraw(address(bob)),
            userInitialAssetDeposit - fee,
            "Bob's max withdraw should be 18000"
        );
    }

    function _handleBobFirstRedeem(UsualXHarness newUsualX) private {
        vm.startPrank(bob);
        uint256 bobMaxRedeem = newUsualX.maxRedeem(bob);
        uint256 bobAssets = newUsualX.redeem(bobMaxRedeem, bob, bob);
        vm.stopPrank();

        uint256 expectedAssets = newUsualX.previewRedeem(bobMaxRedeem);
        assertEq(bobAssets, expectedAssets, "Bob's assets should match preview");
        assertEq(newUsualX.balanceOf(address(bob)), 0, "Bob's shares should be 0");
    }

    function _handleDistributionPeriod(UsualXHarness newUsualX) private returns (uint256) {
        vm.startPrank(registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE));
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;
        newUsualX.startYieldDistribution(10_890_274e18, startTime, endTime);
        vm.stopPrank();

        vm.warp(block.timestamp + 12 hours);
        return endTime;
    }

    function _handleBobSecondDeposit(UsualXHarness newUsualX) private {
        uint256 aliceShares = newUsualX.balanceOf(alice);
        uint256 bobDepositAmount = newUsualX.convertToAssets(aliceShares + 1);

        vm.startPrank(admin);
        usualToken.mint(bob, bobDepositAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        usualToken.approve(address(newUsualX), bobDepositAmount);
        uint256 bobSharesReceived = newUsualX.deposit(bobDepositAmount, bob);
        vm.stopPrank();

        assertEq(
            bobSharesReceived, aliceShares, "Bob should receive same number of shares as alice"
        );
    }

    function _checkFinalState(UsualXHarness newUsualX) private view {
        uint256 aliceFinalAssets = newUsualX.convertToAssets(newUsualX.balanceOf(alice));
        uint256 bobFinalAssets = newUsualX.convertToAssets(newUsualX.balanceOf(bob));
        uint256 deadFinalAssets = newUsualX.convertToAssets(10_000e18) + 1;

        assertEq(
            newUsualX.totalAssets(),
            aliceFinalAssets + bobFinalAssets + deadFinalAssets,
            "Total assets should match converted total supply"
        );
    }

    function _handleFinalWithdrawalsAndDistributions(
        UsualXHarness newUsualX,
        uint256 bobUsualBalanceBefore
    ) private {
        vm.warp(block.timestamp + 100 days);

        uint256 aliceFinalAssets = newUsualX.convertToAssets(newUsualX.balanceOf(alice));
        uint256 bobFinalAssets = newUsualX.convertToAssets(newUsualX.balanceOf(bob));

        vm.startPrank(alice);
        newUsualX.redeem(newUsualX.balanceOf(alice), alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        newUsualX.redeem(newUsualX.balanceOf(bob), bob, bob);
        vm.stopPrank();

        uint256 aliceFee = Math.mulDiv(
            aliceFinalAssets, newUsualX.withdrawFeeBps(), BASIS_POINT_BASE, Math.Rounding.Ceil
        );
        uint256 bobFee = Math.mulDiv(
            bobFinalAssets, newUsualX.withdrawFeeBps(), BASIS_POINT_BASE, Math.Rounding.Ceil
        );

        assertEq(newUsualX.balanceOf(alice), 0, "Alice's shares should be 0");
        assertEq(newUsualX.balanceOf(bob), 0, "Bob's shares should be 0");
        assertEq(
            usualToken.balanceOf(address(alice)),
            aliceFinalAssets - aliceFee,
            "Alice's assets should be the sum of her final assets and dead assets"
        );
        assertEq(
            usualToken.balanceOf(address(bob)) - bobUsualBalanceBefore,
            bobFinalAssets - bobFee,
            "Bob's new assets should be his final assets minus the fee"
        );

        _handleSecondDistribution(newUsualX);
    }

    function _handleSecondDistribution(UsualXHarness newUsualX) private {
        uint256 deadSharesValueBefore = newUsualX.convertToAssets(10_000e18);

        vm.startPrank(registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE));
        newUsualX.startYieldDistribution(500_000e18, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 20 days);

        assertEq(newUsualX.balanceOf(alice), 0, "Alice's shares should be 0");
        assertEq(newUsualX.balanceOf(bob), 0, "Bob's shares should be 0");

        assertApproxEqAbs(
            newUsualX.convertToAssets(10_000e18),
            500_000e18 + deadSharesValueBefore,
            50,
            "Dead shares should absorb all the yield"
        );
    }
}
