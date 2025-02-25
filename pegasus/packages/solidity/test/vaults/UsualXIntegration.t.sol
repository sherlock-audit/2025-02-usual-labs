// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {ONE_MONTH_IN_SECONDS} from "src/mock/constants.sol";

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
    CONTRACT_USUAL,
    BLACKLIST_ROLE,
    CONTRACT_DISTRIBUTION_MODULE,
    MAX_25_PERCENT_WITHDRAW_FEE,
    INITIAL_ACCUMULATED_FEES,
    CONTRACT_USUALX,
    USUALSymbol,
    USUALName,
    USUALXSymbol,
    USUALXName,
    USUALX_WITHDRAW_FEE,
    INITIAL_BURN_RATIO_BPS,
    STARTDATE_USUAL_CLAIMING_DISTRIBUTION_MODULE
} from "src/constants.sol";

import "forge-std/console.sol";

contract UsualXIntegrationTest is SetupTest, UsualX {
    using Math for uint256;

    address public constant distributionModuleAddress = address(0x56897845);

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        vm.deal(alice, 1 ether);
        //set CONTRACT_DISTRIBUTION_MODULE to be a random address
        vm.startPrank(admin);
        registryContract.setContract(CONTRACT_DISTRIBUTION_MODULE, distributionModuleAddress);
        console.log("UsualX totalSupply", usualX.totalSupply());
        vm.stopPrank();
        uint256 initialTotalSupply = usualX.totalSupply();
        assertEq(initialTotalSupply, 10_000e18, "totalSupply should be 10000e18");
    }

    bytes32 constant YIELD_DATA_STORAGE_SLOT =
        0x9a66cc64068466ca9954f77b424b83884332fd82446a2cbd356234cdc6547600;

    // @notice Tests the getBurnRatio function
    function testGetBurnRatio() public view {
        assertEq(usualX.getBurnRatio(), INITIAL_BURN_RATIO_BPS);
    }
    // Helper functions to read YieldDataStorage fields

    function getTotalDeposits() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), YIELD_DATA_STORAGE_SLOT));
    }

    function getPeriodStart() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 2)));
    }

    function getPeriodFinish() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 3)));
    }

    function getLastUpdateTime() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 4)));
    }

    function getIsActive() internal view returns (bool) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 5))) == 1;
    }

    function _calculateTotalWithdraw(uint256 withdrawAmount) internal pure returns (uint256) {
        return withdrawAmount + _calculateFee(withdrawAmount);
    }

    function _calculateFee(uint256 withdrawAmount) internal pure returns (uint256) {
        return
            Math.mulDiv(withdrawAmount, USUALX_WITHDRAW_FEE, BASIS_POINT_BASE, Math.Rounding.Ceil);
    }

    function _calculateFeeTakenFromAmount(uint256 amountMinusFee) internal pure returns (uint256) {
        return Math.mulDiv(
            amountMinusFee,
            USUALX_WITHDRAW_FEE,
            BASIS_POINT_BASE - USUALX_WITHDRAW_FEE,
            Math.Rounding.Ceil
        );
    }

    function testName() external view {
        assertEq(USUALXName, usualX.name());
    }

    function testSymbol() external view {
        assertEq(USUALXSymbol, usualX.symbol());
    }

    function testUsualErc20Compliance() external view {
        ERC165Checker.supportsInterface(address(usualX), type(IERC20).interfaceId);
    }

    function mintTokensToAlice() public {
        vm.prank(admin);
        usualToken.mint(alice, 2e18);
        usualX.deposit(2e18, alice);
        assertEq(usualX.totalSupply(), usualX.balanceOf(alice));
    }

    function testCreationOfUsualXToken() public {
        _resetInitializerImplementation(address(usualX));
        usualX.initialize(address(registryContract), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol);
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usualX));
        //
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualX.initialize(address(0), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol);
    }

    function testInitializeShouldFailWithAmountTooBigWithdrawFee() public {
        _resetInitializerImplementation(address(usualX));
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usualX.initialize(address(registryContract), 2501, USUALXName, USUALXSymbol);
    }

    function testPreviewFunctions() public {
        uint256 depositAmount = 100e18;
        vm.prank(admin);
        usualToken.mint(alice, depositAmount);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        // Test withdraw
        uint256 withdrawAmount = 50e18;
        uint256 expectedSharesWithdraw = usualX.previewWithdraw(withdrawAmount);
        uint256 actualSharesWithdraw = usualX.withdraw(withdrawAmount, alice, alice);
        assertEq(
            expectedSharesWithdraw,
            actualSharesWithdraw,
            "Withdraw: Burned shares should match preview"
        );

        // Test redeem
        uint256 redeemShares = 25e18;
        uint256 expectedAssetsRedeem = usualX.previewRedeem(redeemShares);
        uint256 actualAssetsRedeem = usualX.redeem(redeemShares, alice, alice);
        assertEq(
            expectedAssetsRedeem,
            actualAssetsRedeem,
            "Redeem: Withdrawn assets should match preview"
        );
        vm.stopPrank();

        // Test deposit
        uint256 depositAmount2 = 30e18;
        vm.prank(admin);
        usualToken.mint(alice, depositAmount2);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount2);
        uint256 expectedSharesDeposit = usualX.previewDeposit(depositAmount2);
        uint256 actualSharesDeposit = usualX.deposit(depositAmount2, alice);
        vm.stopPrank();
        assertEq(
            expectedSharesDeposit,
            actualSharesDeposit,
            "Deposit: Minted shares should match preview"
        );

        // Test mint
        uint256 mintShares = 15e18;
        uint256 expectedAssetsMint = usualX.previewMint(mintShares);
        vm.startPrank(alice);
        usualToken.approve(address(usualX), expectedAssetsMint);
        uint256 actualAssetsMint = usualX.mint(mintShares, alice);
        vm.stopPrank();
        assertEq(
            expectedAssetsMint, actualAssetsMint, "Mint: Deposited assets should match preview"
        );
    }

    function testDeposit() public {
        uint256 depositAmount = 10e18;
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        uint256 sharesMinted = usualX.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 deadShares = usualX.balanceOf(address(usualX));
        uint256 deadAssets = usualX.convertToAssets(deadShares);
        assertEq(usualX.balanceOf(alice), sharesMinted, "Incorrect shares minted");
        assertEq(usualX.totalAssets(), depositAmount + deadAssets, "Incorrect total assets");
        assertEq(
            usualToken.balanceOf(address(usualX)),
            depositAmount + deadAssets,
            "Incorrect vault token balance"
        );
    }

    function testDepositWithPermit(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        deal(address(usualToken), alice, amount);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usualX), amount, deadline
        );
        vm.prank(alice);
        usualX.depositWithPermit(amount, alice, deadline, v, r, s);
        uint256 deadShares = usualX.balanceOf(address(usualX));
        uint256 deadAssets = usualX.convertToAssets(deadShares);

        assertEq(usualX.balanceOf(alice), amount, "Incorrect shares minted");
        assertEq(usualX.totalAssets(), amount + deadAssets, "Incorrect total assets");
        assertEq(
            usualToken.balanceOf(address(usualX)),
            amount + deadAssets,
            "Incorrect vault token balance"
        );
    }

    function testDepositWithPermitFailsWithInvalidPermit() public {
        uint256 depositAmount = 10e18;

        deal(address(usualToken), alice, depositAmount);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usualX), depositAmount, deadline
        );

        vm.startPrank(alice);

        // bad v
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, 0, r, s);
        vm.stopPrank();

        // bad r
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, v, bytes32(0), s);
        vm.stopPrank();

        // bad s
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, v, r, bytes32(0));
        vm.stopPrank();

        // bad deadline
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline + 1, v, r, s);
        vm.stopPrank();
    }

    function testWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 100e18, 1_000_000e18);
        withdrawAmount = bound(withdrawAmount, 50e18, depositAmount / 2);

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        uint256 initialTotalAssets = usualX.totalAssets();
        uint256 initialAliceBalance = usualToken.balanceOf(alice);
        uint256 initialDeadAssets = usualX.convertToAssets(usualX.balanceOf(address(usualX)));
        assertEq(
            usualX.totalAssets(),
            depositAmount + initialDeadAssets,
            "Total assets should match deposit amount"
        );
        assertEq(
            usualToken.balanceOf(address(usualX)),
            depositAmount + initialDeadAssets,
            "Vault token balance should match deposit amount"
        );

        // Calculate the expected shares burned
        uint256 expectedSharesBurned = usualX.previewWithdraw(withdrawAmount);

        // Perform withdrawal
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Check that the shares burned correspond to the total amount withdrawn (including fee)
        assertEq(sharesBurned, expectedSharesBurned, "Shares burned should match preview");
        // Calculate total assets needed, including fee
        uint256 assetsWithFee = (withdrawAmount + _calculateFeeTakenFromAmount(withdrawAmount));
        assertEq(
            assetsWithFee,
            Math.mulDiv(
                withdrawAmount,
                BASIS_POINT_BASE,
                (BASIS_POINT_BASE - USUALX_WITHDRAW_FEE),
                Math.Rounding.Ceil
            ),
            "Fee should be 5% of withdrawn amount"
        );

        // Assertions
        assertEq(
            usualToken.balanceOf(alice),
            initialAliceBalance + withdrawAmount,
            "User should receive exact requested amount"
        );
        assertEq(
            usualX.totalAssets(),
            initialTotalAssets - assetsWithFee,
            "Total assets should decrease by withdrawn amount plus fee"
        );

        // Verify that totalDeposited in the vault has decreased by the full amount (withdraw + fee)
        uint256 expectedTotalDeposited = initialTotalAssets - assetsWithFee;
        assertEq(
            usualX.totalAssets(),
            expectedTotalDeposited,
            "Total deposited should decrease by withdraw amount plus fee"
        );
    }

    function testWithdrawAboveMaxFails() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 100e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);
        uint256 maxAssetsAliceCanWithdraw = usualX.maxWithdraw(alice);
        // Perform withdrawal
        assertGt(
            withdrawAmount, maxAssetsAliceCanWithdraw, "Trying to withdraw more than max allowed"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxWithdraw.selector,
                alice,
                withdrawAmount,
                maxAssetsAliceCanWithdraw
            )
        );
        usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();
    }

    function testRedeemAboveMaxFails() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 101e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);
        uint256 maxSharesAliceCanRedeem = usualX.maxRedeem(alice);
        // Perform withdrawal
        assertGt(withdrawAmount, maxSharesAliceCanRedeem, "Trying to redeem more than max allowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxRedeem.selector, alice, withdrawAmount, maxSharesAliceCanRedeem
            )
        );
        usualX.redeem(withdrawAmount, alice, alice);
        vm.stopPrank();
    }

    function testPrecisionAt1BPS() public pure {
        // Test array of amounts ranging from 1 wei to max possible withdrawal
        uint256[] memory testAmounts = new uint256[](6);
        testAmounts[0] = 1; // 1 wei (minimum amount)
        testAmounts[1] = 100; // 100 wei (very small amount)
        testAmounts[2] = 100_000; // 0.0001 ether (medium amount)
        testAmounts[3] = 1e18; // 1 ether (standard amount)
        testAmounts[4] = 1e20; // 100 ether (large amount)
        testAmounts[5] = type(uint256).max - _calculateFee(type(uint256).max); // maximum possible withdrawal

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 withdrawAmount = testAmounts[i];

            // Calculate fee two different ways:
            // 1. Using the contract's fee calculation method
            uint256 calculatedFee = _calculateFeeTakenFromAmount(withdrawAmount);

            // 2. Using simple subtraction after total calculation
            uint256 totalWithdraw = withdrawAmount + calculatedFee;
            uint256 directFee = totalWithdraw - withdrawAmount;

            // For very small amounts (< 100 wei), we expect a 1 wei fee
            if (withdrawAmount < 100) {
                assertEq(directFee, 1, "Small amounts should have 1 wei fee");
                continue;
            }

            // For normal amounts, both fee calculations should match exactly
            assertEq(calculatedFee, directFee, "Fee calculations should match exactly");
        }
    }

    function testYieldDistribution1() public {
        uint256 initialDeposit = 100e18;
        uint256 yieldAmount = 24e18;
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);

        console.log("UsualX totalSupply 2 ", usualX.totalSupply());
        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();
        console.log("usualX aliceBalanceBefore", usualX.balanceOf(address(alice)));
        console.log("UsualX totalSupply 3 ", usualX.totalSupply());
        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        vm.warp(startTime); // Warp to start of yield period
        uint256 initialTotalAssets = usualX.totalAssets();

        vm.warp(endTime + 1); // Warp to end of yield period
        uint256 finalTotalAssets = usualX.totalAssets();

        assertEq(finalTotalAssets, initialTotalAssets + yieldAmount, "Incorrect final total assets");
    }

    function testDepositAfterDistribution() public {
        // we will deposit 1M usual tokens to the vault
        uint256 initialDeposit = 1_000_000e18;
        // we are going to yield 10M usual tokens before that (as in prod right now)
        uint256 yieldAmount = 10_000_000e18;
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        // Warp to end of yield period
        uint256 initialTotalAssets = usualX.totalAssets();
        assertEq(initialTotalAssets, 10_000e18, "initialTotalAssets should be 0");
        uint256 initialTotalSupply = usualX.totalSupply();
        assertEq(initialTotalSupply, 10_000e18, "totalSupply should be 10000e18");
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 1 days;
        // distribute the yield
        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount - 10_000e18, startTime, endTime);
        vm.warp(endTime + 1);
        // now empty vault ,  10M yield already distributed  to the vault and no shares
        assertEq(usualX.totalAssets(), yieldAmount);
        assertEq(usualX.totalSupply(), 10_000e18);
        // alice want to deposit 1M usual tokens to the vault
        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        //  the total assets of the vault should be 11M usual tokens
        assertEq(usualX.totalAssets(), initialDeposit + yieldAmount, "Incorrect final total assets");
        // some shares should be minted to alice
        assertGt(usualX.balanceOf(alice), 0, " some shares should be minted to alice");
    }

    function testMultiUserYieldDistribution() public {
        uint256 aliceDeposit = 50e18;
        uint256 bobDeposit = 100e18;
        uint256 yieldAmount = 24e18;

        vm.startPrank(admin);
        usualToken.mint(alice, aliceDeposit);
        usualToken.mint(bob, bobDeposit);
        vm.stopPrank();

        // Get initial dead shares
        uint256 initialDeadShares = usualX.balanceOf(address(usualX));
        uint256 initialDeadAssets = usualX.convertToAssets(initialDeadShares);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), aliceDeposit);
        usualX.deposit(aliceDeposit, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usualToken.approve(address(usualX), bobDeposit);
        usualX.deposit(bobDeposit, bob);
        vm.stopPrank();

        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        vm.warp(endTime);

        uint256 totalInitialDeposit = aliceDeposit + bobDeposit + initialDeadAssets;
        uint256 totalFinalAssets = totalInitialDeposit + yieldAmount;

        // Calculate expected assets considering dead shares
        uint256 expectedAliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        uint256 expectedBobAssets = usualX.convertToAssets(usualX.balanceOf(bob));

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        uint256 bobAssets = usualX.convertToAssets(usualX.balanceOf(bob));

        assertApproxEqAbs(aliceAssets, expectedAliceAssets, 1, "Incorrect assets for Alice");
        assertApproxEqAbs(bobAssets, expectedBobAssets, 1, "Incorrect assets for Bob");
        assertApproxEqAbs(
            aliceAssets * 2, bobAssets, 1, "Bob should have exactly twice the assets of Alice"
        );
    }

    function testMultipleYieldPeriods() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 yield2 = 50e18;

        // Get initial dead shares and assets
        uint256 initialDeadShares = usualX.balanceOf(address(usualX));
        uint256 initialDeadAssets = usualX.convertToAssets(initialDeadShares);

        // Log initial state
        console.log("Initial Dead Shares:", initialDeadShares);
        console.log("Initial Dead Assets:", initialDeadAssets);

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // Record state after deposit
        uint256 totalAssetsAfterDeposit = usualX.totalAssets();
        console.log("Total Assets After Deposit:", totalAssetsAfterDeposit);

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(endTime1);

        // Record state after first yield
        uint256 totalAssetsAfterYield1 = usualX.totalAssets();
        console.log("Total Assets After Yield 1:", totalAssetsAfterYield1);

        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);

        // Calculate expected total assets including dead shares
        uint256 expectedTotalAssets = initialDeposit + initialDeadAssets + yield1 + yield2;

        // Log final state
        console.log("Expected Total Assets:", expectedTotalAssets);
        console.log("Actual Total Assets:", usualX.totalAssets());

        assertEq(
            usualX.totalAssets(),
            expectedTotalAssets,
            "Total assets should include initial dead shares and both yield periods"
        );

        // Calculate Alice's expected assets (proportional to her share of total shares)
        uint256 aliceShares = usualX.balanceOf(alice);
        uint256 totalShares = usualX.totalSupply();
        uint256 aliceAssets = usualX.convertToAssets(aliceShares);
        uint256 expectedAliceAssets =
            Math.mulDiv(expectedTotalAssets, aliceShares, totalShares, Math.Rounding.Floor);

        assertApproxEqAbs(
            aliceAssets,
            expectedAliceAssets,
            1,
            "Alice's assets should be proportional to her share"
        );
    }

    function testMultipleYieldOverlappingPeriods() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 yield2 = 50e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // Set initial timestamp
        vm.warp(STARTDATE_USUAL_CLAIMING_DISTRIBUTION_MODULE); // Start at a known timestamp

        // First yield period setup
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp;
        uint256 endTime1 = startTime1 + 1 days;

        console.log("First Period Start:", startTime1);
        console.log("First Period End:", endTime1);

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        // Try to start second period before first one ends
        vm.warp(startTime1 + 12 hours); // Warp to middle of first period

        console.log("Current Time:", block.timestamp);
        console.log("Attempting Second Period Start");

        // Second yield period attempt
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = block.timestamp;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        vm.expectRevert(StartTimeBeforePeriodFinish.selector);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        // Verify first period is still active
        assertLt(block.timestamp, endTime1, "Current time should be before first period end");
    }

    function testYieldWithIntermediateDeposits() public {
        uint256 currentAssets = usualX.totalAssets();
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 bobDeposit = 500e18;
        uint256 yield2 = 50e18;

        // Alice's initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        usualToken.mint(bob, bobDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(startTime1 + 12 hours);

        // Bob deposits midway through first yield period
        vm.startPrank(bob);
        usualToken.approve(address(usualX), bobDeposit);
        usualX.deposit(bobDeposit, bob);
        vm.stopPrank();

        vm.warp(endTime1);

        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);

        uint256 expectedTotalAssets = initialDeposit + bobDeposit + yield1 + yield2;
        assertEq(
            usualX.totalAssets(),
            expectedTotalAssets + currentAssets,
            "Total assets should include both deposits and both yield periods"
        );

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        uint256 bobAssets = usualX.convertToAssets(usualX.balanceOf(bob));
        uint256 baseAssets = usualX.convertToAssets(usualX.balanceOf(address(usualX)));
        // Alice should have more assets than Bob due to being in the vault for longer
        assertGt(aliceAssets, bobAssets, "Alice should have more assets than Bob");

        // The sum of Alice and Bob's assets should equal the total assets
        assertApproxEqAbs(
            aliceAssets + bobAssets + baseAssets,
            expectedTotalAssets + currentAssets,
            2,
            "Sum of Alice and Bob's assets should equal total assets"
        );
    }

    function testYieldWithIntermediateWithdrawal() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 yield2 = 50e18;
        uint256 aliceWithdrawal = 300e18;

        // Get initial dead shares
        uint256 initialDeadShares = usualX.balanceOf(address(usualX));
        uint256 initialDeadAssets = usualX.convertToAssets(initialDeadShares);
        uint256 initialTotalAssets = usualX.totalAssets();

        // Initial deposit setup
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        uint256 initialAliceShares = usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // Verify initial state
        assertEq(usualX.balanceOf(alice), initialAliceShares, "Initial shares mismatch");
        assertEq(
            usualX.totalAssets(),
            initialDeposit + initialDeadAssets,
            "Initial total assets mismatch"
        );

        // Execute first yield period and withdrawal
        (
            uint256 aliceFinalShares,
            uint256 deadShares,
            uint256 firstPeriodYield,
            uint256 firstPeriodWithdrawalFee
        ) = _executeFirstYieldPeriodAndWithdrawal(yield1, aliceWithdrawal, initialAliceShares);

        // Execute second yield period
        uint256 secondPeriodYield = _executeSecondYieldPeriod(yield2, aliceFinalShares, deadShares);

        // Verify first period end state
        assertEq(
            usualX.totalAssets(),
            // initialTotalAssets + firstDeposit + firstYield + secondYield - aliceWithdrawal - firstPeriodWithdrawalFee
            initialTotalAssets + 1000e18 + 100e18 + 50e18 - 300e18 - firstPeriodWithdrawalFee,
            "First period final assets incorrect"
        );
    }

    function _executeFirstYieldPeriodAndWithdrawal(
        uint256 yield1,
        uint256 aliceWithdrawal,
        uint256 initialAliceShares
    )
        internal
        returns (
            uint256 aliceFinalShares,
            uint256 deadShares,
            uint256 firstPeriodYield,
            uint256 firstPeriodWithdrawalFee
        )
    {
        uint256 initialTotalAssets = usualX.totalAssets();

        // First yield period setup
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        // Move to middle of first period and verify half yield
        vm.warp(startTime1 + 12 hours);
        uint256 halfYield = yield1 / 2;
        assertApproxEqAbs(
            usualX.totalAssets(),
            initialTotalAssets + halfYield,
            1,
            "Half yield not correctly distributed"
        );

        // Alice withdraws
        vm.prank(alice);
        uint256 sharesBurned = usualX.withdraw(aliceWithdrawal, alice, alice);
        firstPeriodWithdrawalFee = _calculateFeeTakenFromAmount(aliceWithdrawal);

        // Verify withdrawal
        assertEq(
            usualX.balanceOf(alice),
            initialAliceShares - sharesBurned,
            "Shares not correctly burned"
        );

        // Complete first period
        vm.warp(endTime1);
        firstPeriodYield = yield1;
        aliceFinalShares = usualX.balanceOf(alice);
        deadShares = usualX.balanceOf(address(usualX));

        // Verify first period end state
        assertEq(
            usualX.totalAssets(),
            initialTotalAssets + yield1 - aliceWithdrawal - firstPeriodWithdrawalFee,
            "First period final assets incorrect"
        );
    }

    function _executeSecondYieldPeriod(uint256 yield2, uint256 aliceFinalShares, uint256 deadShares)
        internal
        returns (uint256 secondPeriodYield)
    {
        uint256 initialTotalAssets = usualX.totalAssets();

        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = block.timestamp;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);
        secondPeriodYield = yield2;

        // Calculate Alice's proportion of second yield
        uint256 totalSupply = usualX.totalSupply();
        uint256 expectedYield =
            Math.mulDiv(yield2, aliceFinalShares, totalSupply - deadShares, Math.Rounding.Floor);

        // Verify second period end state
        assertEq(
            usualX.totalAssets(),
            initialTotalAssets + yield2,
            "Second period final assets incorrect"
        );

        return expectedYield;
    }

    function testDepositAndMintRevertsWhenPaused() public {
        vm.prank(pauser);
        usualX.pause();

        uint256 amount = 100e18;
        vm.prank(admin);
        usualToken.mint(alice, amount);

        vm.prank(alice);
        usualToken.approve(address(usualX), amount);

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(alice);
        usualX.deposit(amount, alice);

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(alice);
        usualX.mint(amount, alice);
    }

    function testComplexYieldScenario() public {
        // Initial setup
        address[] memory users = new address[](3);
        uint256 expectedTotalAssets = 0;
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256 initialMint = 10_000e18;
        uint256 initialDeposit = 1000e18;

        // Initial deposits
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(admin);
            usualToken.mint(users[i], initialMint);

            vm.startPrank(users[i]);
            usualToken.approve(address(usualX), initialMint);
            usualX.deposit(initialDeposit, users[i]);
            vm.stopPrank();
        }

        // Account for initial deposits and dead shares
        uint256 deadShares = usualX.balanceOf(address(usualX));
        uint256 deadAssets = usualX.convertToAssets(deadShares);
        expectedTotalAssets = (initialDeposit * 3) + deadAssets;

        // First yield period setup
        uint256 yield1 = 300e18;
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        // Mid first yield period
        vm.warp(startTime1 + 12 hours);
        expectedTotalAssets += yield1 / 2;

        // Alice withdraws
        uint256 aliceWithdraw = 200e18;
        uint256 aliceWithdrawFee = _calculateFeeTakenFromAmount(aliceWithdraw);
        vm.prank(alice);
        usualX.withdraw(aliceWithdraw, alice, alice);
        expectedTotalAssets -= (aliceWithdraw + aliceWithdrawFee);

        // Bob deposits
        vm.prank(bob);
        usualX.deposit(500e18, bob);
        expectedTotalAssets += 500e18;

        // End of first yield period
        vm.warp(endTime1);
        expectedTotalAssets += yield1 / 2;

        // Second yield period setup
        uint256 yield2 = 200e18;
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        // Mid second yield period
        vm.warp(startTime2 + 12 hours);
        expectedTotalAssets += yield2 / 2;

        // Carol withdraws
        uint256 carolWithdraw = 500e18;
        uint256 carolWithdrawFee = _calculateFeeTakenFromAmount(carolWithdraw);
        vm.prank(carol);
        usualX.withdraw(carolWithdraw, carol, carol);
        expectedTotalAssets -= (carolWithdraw + carolWithdrawFee);

        // Alice deposits
        vm.prank(alice);
        usualX.deposit(300e18, alice);
        expectedTotalAssets += 300e18;

        // End of second yield period
        vm.warp(endTime2);
        expectedTotalAssets += yield2 / 2;

        // Final assertions
        uint256 assetTotal = expectedTotalAssets;
        uint256 actualTotalAssets = usualX.totalAssets();
        assertApproxEqAbs(
            actualTotalAssets, assetTotal, 1, "Total assets should match expected value"
        );

        // Verify relative asset positions
        assertGt(
            usualX.convertToAssets(usualX.balanceOf(bob)),
            usualX.convertToAssets(usualX.balanceOf(alice)),
            "Bob should have more assets than Alice"
        );
        assertGt(
            usualX.convertToAssets(usualX.balanceOf(bob)),
            usualX.convertToAssets(usualX.balanceOf(carol)),
            "Bob should have more assets than Carol"
        );
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.unpause();
    }

    function testPauseUnPauseShouldWorkWhenAuthorized() external {
        vm.prank(pauser);
        usualX.pause();
        vm.prank(admin);
        usualX.unpause();
    }

    function testBurnFromVault() public {
        vm.startPrank(admin);
        usualToken.mint(alice, 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);
        vm.stopPrank();

        vm.prank(address(usualX));
        usualToken.burnFrom(alice, 8e18);
        uint256 deadShares = usualX.balanceOf(address(usualX));
        assertEq(usualToken.totalSupply(), 2e18 + deadShares);
        assertEq(usualToken.balanceOf(alice), 2e18);
    }

    function testBlacklistShouldRevertIfAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        usualX.blacklist(address(0));
    }

    function testBlacklistAndUnBlacklistEmitsEvents() external {
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usualX.blacklist(alice);

        vm.expectEmit();
        emit UnBlacklist(alice);
        usualX.unBlacklist(alice);
        vm.stopPrank();
    }

    function testOnlyBlacklistRoleCanUseBlacklist(address user) external {
        vm.assume(user != blacklistOperator);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.blacklist(alice);

        vm.prank(blacklistOperator);
        usualX.blacklist(alice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.unBlacklist(alice);
    }

    function testNoDoubleBlacklist() external {
        vm.prank(blacklistOperator);
        usualX.blacklist(alice);

        vm.prank(blacklistOperator);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualX.blacklist(alice);

        assertEq(usualX.isBlacklisted(alice), true);

        vm.prank(blacklistOperator);
        usualX.unBlacklist(alice);

        vm.prank(blacklistOperator);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualX.unBlacklist(alice);
    }

    function testTransferFrom() public {
        uint256 amount = 100e18;
        vm.prank(admin);
        usualToken.mint(alice, amount);

        vm.prank(alice);
        usualToken.approve(address(usualX), amount);

        vm.prank(alice);
        usualX.deposit(amount, alice);

        vm.prank(alice);
        usualX.approve(bob, amount);

        vm.prank(bob);
        assertTrue(usualX.transferFrom(alice, carol, amount));

        assertEq(usualX.balanceOf(carol), amount);
        assertEq(usualX.balanceOf(alice), 0);
    }

    function testUpdateWithdrawFee() public {
        uint256 newFee = 200; // 2%
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        assertEq(usualX.withdrawFeeBps(), newFee, "Withdraw fee should be updated");
    }

    function testUpdateWithdrawFeeEmitsEvent() public {
        uint256 newFee = 200; // 2%
        vm.prank(withdrawFeeUpdater);
        vm.expectEmit(true, false, false, true);
        emit WithdrawFeeUpdated(newFee);
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeFailsNotAdmin() public {
        uint256 newFee = 200; // 2%
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeFailsExceedsMax() public {
        uint256 newFee = MAX_25_PERCENT_WITHDRAW_FEE + 1;
        vm.prank(withdrawFeeUpdater);
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeAffectsWithdrawals() public {
        uint256 initialDeposit = 1000e18;
        uint256 withdrawAmount = 100e18;
        uint256 newFee = 200; // 2%

        // Setup
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // Update fee
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        // Calculate expected fee before withdrawal
        uint256 expectedFee =
            Math.mulDiv(withdrawAmount, newFee, BASIS_POINT_BASE - newFee, Math.Rounding.Ceil);
        uint256 expectedSharesBurned = usualX.convertToShares(withdrawAmount + expectedFee);

        // Withdraw
        vm.prank(alice);
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);

        assertEq(sharesBurned, expectedSharesBurned, "Incorrect shares burned after fee update");
    }

    function testUpdateWithdrawFeeZero() public {
        uint256 newFee = 0;
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        assertEq(usualX.withdrawFeeBps(), newFee, "Withdraw fee should be updated to zero");
    }

    function testStartYieldDistributionZeroAmount() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(ZeroYieldAmount.selector);
        usualX.startYieldDistribution(0, block.timestamp + 1 hours, block.timestamp + 2 hours);
    }

    function testStartYieldDistribution_RevertsIfNotDistributionModule() public {
        vm.expectRevert(NotAuthorized.selector);
        usualX.startYieldDistribution(100e18, block.timestamp + 1 hours, block.timestamp + 2 hours);
    }

    function testStartYieldDistributionPastStartTime() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(StartTimeNotInFuture.selector);
        usualX.startYieldDistribution(100e18, block.timestamp - 1, block.timestamp + 1 hours);
    }

    function testStartYieldDistributionEndTimeBeforeStartTime() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(EndTimeNotAfterStartTime.selector);
        usualX.startYieldDistribution(100e18, block.timestamp + 2 hours, block.timestamp + 1 hours);
    }

    function testStartYieldDistributionStartTimeBeforePeriodFinish() public {
        testStartYieldDistributionSuccess();

        vm.prank(distributionModuleAddress);
        vm.expectRevert(StartTimeBeforePeriodFinish.selector);
        usualX.startYieldDistribution(100e18, block.timestamp, block.timestamp + 2 hours);
    }

    function testStartYieldDistributionInsufficientAssets() public {
        uint256 yieldAmount = 100e18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        // Get current total deposits (including dead shares)
        uint256 totalDeposits = usualX.totalAssets();

        // Calculate total required assets (yield + existing deposits)
        uint256 totalRequiredAssets = totalDeposits + yieldAmount;

        // Ensure the contract doesn't have enough assets for yield + deposits
        assertLt(
            usualToken.balanceOf(address(usualX)),
            totalRequiredAssets,
            "Test setup: contract should not have enough assets for yield + deposits"
        );

        vm.prank(distributionModuleAddress);
        vm.expectRevert(InsufficientAssetsForYield.selector);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);
    }

    function testStartYieldDistributionSuccess() public {
        uint256 yieldAmount = 100e18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        // Ensure the contract has enough assets
        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 initialTotalDeposits = getTotalDeposits();

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        // Verify that the yield distribution started successfully
        assertTrue(getIsActive(), "Yield distribution should be active");
        assertEq(getPeriodStart(), startTime, "Start time should be set correctly");
        assertEq(getPeriodFinish(), endTime, "End time should be set correctly");
        assertEq(getLastUpdateTime(), startTime, "Last update time should be set to start time");
        assertTrue(usualX.getYieldRate() > 0, "Yield rate should be set");

        // Verify that totalDeposits hasn't changed
        assertEq(getTotalDeposits(), initialTotalDeposits, "Total deposits should not change");

        // Calculate and verify the yield rate
        uint256 expectedYieldRate = (yieldAmount * YIELD_PRECISION) / (endTime - startTime);
        assertEq(
            usualX.getYieldRate(), expectedYieldRate, "Yield rate should be calculated correctly"
        );
    }

    function testConstructorDoesNotRevert() public {
        UsualX newUsualX = new UsualX();
        assertTrue(address(newUsualX) != address(0), "Constructor should not revert");
    }

    // @notice Tests the sweepFees function
    // @param depositAmount The amount of assets initially deposited
    // @param withdrawAmount The amount of assets initially withdrawn
    function testSweepFees(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 100e18, 1_000_000e18);
        withdrawAmount = bound(withdrawAmount, 50e18, depositAmount / 2);

        // Get initial dead shares
        uint256 initialDeadShares = usualX.balanceOf(address(usualX));
        uint256 initialDeadAssets = usualX.convertToAssets(initialDeadShares);

        // Initial deposit setup
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        // Record initial state
        uint256 initialTotalAssets = usualX.totalAssets();
        uint256 initialAliceBalance = usualToken.balanceOf(alice);

        // Perform withdrawal to generate fees
        uint256 expectedSharesBurned = usualX.previewWithdraw(withdrawAmount);
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Calculate withdrawal fee
        uint256 withdrawFee = _calculateFeeTakenFromAmount(withdrawAmount);
        uint256 assetsWithFee = withdrawAmount + withdrawFee;

        // Get burn ratio (33.33% initially)
        uint256 burnRatio = usualX.getBurnRatio();

        // Get accumulated fees and initial total supply
        uint256 accumulatedFees = usualX.getAccumulatedFees();
        uint256 usualTotalSupply = usualToken.totalSupply();

        // Calculate expected amounts
        uint256 expectedTreasuryAmount = accumulatedFees.mulDiv(
            BASIS_POINT_BASE - burnRatio, BASIS_POINT_BASE, Math.Rounding.Floor
        );
        uint256 expectedBurnAmount =
            accumulatedFees.mulDiv(burnRatio, BASIS_POINT_BASE, Math.Rounding.Floor);

        // Sweep fees
        vm.prank(feeSweeper);
        usualX.sweepFees();

        console.log("expectedTreasuryAmount", expectedTreasuryAmount);
        console.log("expectedBurnAmount", expectedBurnAmount);
        // Verify treasury received correct amount (66.67% of fees)
        assertApproxEqAbs(
            usualToken.balanceOf(treasuryYield),
            expectedTreasuryAmount,
            1,
            "Treasury should receive 66.67% of accumulated fees"
        );

        // Verify correct amount was burned (33.33% of fees)
        assertApproxEqAbs(
            usualToken.totalSupply(),
            usualTotalSupply - expectedBurnAmount,
            1,
            "Total supply should decrease by 33.33% of accumulated fees"
        );

        // Verify final total assets
        assertApproxEqAbs(
            usualX.totalAssets(),
            initialTotalAssets - assetsWithFee,
            1,
            "Total assets should reflect withdrawal and fees"
        );

        // Verify alice received correct withdrawal amount
        assertApproxEqAbs(
            usualToken.balanceOf(alice),
            initialAliceBalance + withdrawAmount,
            1,
            "Alice should receive exact withdrawal amount"
        );

        // Verify shares burned matches preview
        assertEq(sharesBurned, expectedSharesBurned, "Actual shares burned should match preview");
    }

    // @notice Tests the sweepFees function by fuzzing the burn ratio
    // @param burnRatio The burn ratio to test
    function testSweepFeesWithDifferentBurnRatio(uint256 burnRatio) public {
        burnRatio = bound(burnRatio, 0, BASIS_POINT_BASE);

        // Update the burn ratio
        vm.prank(burnRatioUpdater);
        usualX.setBurnRatio(burnRatio);
        assertEq(usualX.getBurnRatio(), burnRatio, "Burn ratio should be updated");

        // Get initial dead shares
        uint256 initialDeadShares = usualX.balanceOf(address(usualX));
        uint256 initialDeadAssets = usualX.convertToAssets(initialDeadShares);

        // Setup deposit and withdrawal
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        uint256 initialTotalAssets = usualX.totalAssets();
        uint256 initialAliceBalance = usualToken.balanceOf(alice);

        // Calculate expected shares burned for withdrawal
        uint256 expectedSharesBurned = usualX.previewWithdraw(withdrawAmount);

        // Perform withdrawal
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Calculate fee
        uint256 withdrawFee = _calculateFeeTakenFromAmount(withdrawAmount);
        uint256 assetsWithFee = withdrawAmount + withdrawFee;

        // Get accumulated fees
        uint256 accumulatedFees = usualX.getAccumulatedFees();

        // Get the Usual total supply before sweep
        uint256 usualTotalSupply = usualToken.totalSupply();

        // Sweep fees
        vm.prank(feeSweeper);
        usualX.sweepFees();

        // Calculate expected amounts after sweep
        uint256 expectedTreasuryAmount = accumulatedFees.mulDiv(
            BASIS_POINT_BASE - burnRatio, BASIS_POINT_BASE, Math.Rounding.Floor
        );
        uint256 expectedBurnAmount =
            accumulatedFees.mulDiv(burnRatio, BASIS_POINT_BASE, Math.Rounding.Floor);

        // Verify that the treasury received the correct amount of fees
        assertApproxEqAbs(
            usualToken.balanceOf(treasuryYield),
            expectedTreasuryAmount,
            1,
            "Treasury should receive the correct amount of fees"
        );

        // Verify that the total supply decreased by the correct amount because of the burn
        assertApproxEqAbs(
            usualToken.totalSupply(),
            usualTotalSupply - expectedBurnAmount,
            1,
            "Total supply should decrease by the correct amount"
        );

        // Verify final total assets includes dead shares
        assertApproxEqAbs(
            usualX.totalAssets(),
            initialTotalAssets - assetsWithFee,
            1,
            "Total assets should reflect withdrawal and fees"
        );
    }

    // @notice Tests the sweepFees function by fuzzing the deposit and withdraw amounts
    // @param depositAmount The amount of assets initially deposited
    // @param withdrawAmount The amount of assets initially withdrawn
    function testSweepFeesEmitsEvent(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 100e18, 1_000_000e18);
        withdrawAmount = bound(withdrawAmount, 50e18, depositAmount / 2);

        // Initial deposit setup
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        // Perform withdrawal to generate fees
        usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Get burn ratio and total accumulated fees
        uint256 burnRatio = usualX.getBurnRatio();
        uint256 totalFees = usualX.getAccumulatedFees();

        // Calculate burn amount (this matches the contract's calculation)
        uint256 burnAmount =
            Math.mulDiv(totalFees, burnRatio, BASIS_POINT_BASE, Math.Rounding.Floor);

        // Log values for verification
        console.log("Total Fees:", totalFees);
        console.log("Burn Amount:", burnAmount);
        console.log("Transfer Amount:", totalFees - burnAmount);

        // Expect the event with exact parameters from sweepFees implementation
        vm.expectEmit(true, false, false, true, address(usualX));
        emit FeeSwept(treasuryYield, totalFees, burnAmount);

        // Sweep the fees
        vm.prank(feeSweeper);
        usualX.sweepFees();

        // Verify actual state changes
        assertEq(usualX.getAccumulatedFees(), 0, "Accumulated fees should be reset");
        assertEq(
            usualToken.balanceOf(treasuryYield),
            totalFees - burnAmount,
            "Treasury should receive total fees minus burned amount"
        );
    }
}
