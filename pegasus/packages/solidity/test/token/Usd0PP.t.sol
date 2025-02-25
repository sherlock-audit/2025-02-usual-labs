// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SetupTest} from "test/setup.t.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {Usd0PPHarness} from "src/mock/token/Usd0PPHarness.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {Approval as PermitApproval} from "src/interfaces/IDaoCollateral.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {
    CONTRACT_USD0PP,
    CONTRACT_TREASURY,
    BOND_DURATION_FOUR_YEAR,
    PEG_MAINTAINER_ROLE,
    USYC,
    EARLY_BOND_UNLOCK_ROLE,
    PAUSING_CONTRACTS_ROLE,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    END_OF_EARLY_UNLOCK_PERIOD,
    UNWRAP_CAP_ALLOCATOR_ROLE,
    USD0PP_CAPPED_UNWRAP_ROLE,
    PEG_MAINTAINER_UNLIMITED_ROLE,
    BASIS_POINT_BASE,
    DEFAULT_ADMIN_ROLE,
    USD0PP_USUAL_DISTRIBUTION_ROLE,
    USD0PP_DURATION_COST_FACTOR_ROLE,
    USD0PP_TREASURY_ALLOCATION_RATE_ROLE,
    USD0PP_TARGET_REDEMPTION_RATE_ROLE,
    USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS
} from "src/constants.sol";
import {
    BeginInPast,
    BondNotStarted,
    OutsideEarlyUnlockTimeframe,
    BondNotFinished,
    BondFinished,
    InvalidName,
    InvalidSymbol,
    AmountIsZero,
    Blacklisted,
    PARNotRequired,
    PARUSD0InputExceedsBalance,
    NotPermittedToEarlyUnlock,
    NullAddress,
    InvalidInput,
    InvalidInputArraysLength,
    NotAuthorized,
    FloorPriceTooHigh,
    InsufficientUsd0ppBalance,
    AmountMustBeGreaterThanZero,
    FloorPriceNotSet,
    OutOfBounds,
    UnwrapCapNotSet,
    AmountTooBigForCap,
    UsualAmountTooLow,
    UsualAmountIsZero
} from "src/errors.sol";

import {CURVE_POOL, USYC_PRICE_FEED_MAINNET} from "src/mock/constants.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

contract Usd0PPTest is SetupTest {
    struct RedemptionScenario {
        uint256 userRedemption;
        uint256 weeklyOutflows;
        uint256 weeklyInflows;
        uint256 tvl;
        uint256 targetRedemptionRate;
        uint256 usualDistributionPerUsd0pp;
        uint256 durationCostFactor;
        uint256 expectedUsual;
    }

    address public rwa;
    ICurvePool public curvePool;

    event PARMechanismActivated(address indexed user, uint256 amount);
    event RedemptionsStatus(address indexed account, bool disabledForTemporaryRedemptions);
    event BondUnwrappedDuringEarlyUnlock(address indexed user, uint256 amount);
    event Usd0ppUnlockedFloorPrice(address indexed user, uint256 usd0ppAmount, uint256 usd0Amount);
    event BondEarlyUnlockDisabled(address indexed user);
    event EarlyUnlockBalancesSet(address[] addressesToAllocateTo, uint256[] earlyUnlockBalances);
    event EarlyUnlockPeriodSet(uint256 earlyUnlockStart, uint256 earlyUnlockEnd);
    event DurationCostFactorSet(uint256 newFactor);
    event UsualDistributionPerUsd0ppSet(uint256 newRate);
    event TargetRedemptionRateSet(uint256 newRate);
    event TreasuryAllocationRateSet(uint256 newRate);
    event UnwrapCapSet(address indexed user, uint256 cap);
    event CappedUnwrap(address indexed user, uint256 amount, uint256 remainingUnwrapAllowance);

    function setUp() public virtual override {
        super.setUp();
    }

    function _createRwa() internal {
        vm.prank(admin);
        rwa = rwaFactory.createRwa("rwa", "rwa", 6);
        whitelistPublisher(address(rwa), address(stbcToken));

        _setupBucket(address(rwa), address(stbcToken));

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1.1e18);
        treasury = address(registryContract.getContract(CONTRACT_TREASURY));

        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwa),
            abi.encode(1e6)
        );

        deal(rwa, treasury, type(uint128).max);
    }

    function testAnyoneCanCreateUsd0PP() public {
        Usd0PPHarness usd0PP = new Usd0PPHarness();
        _resetInitializerImplementation(address(usd0PP));
        usd0PP.initialize(
            address(registryContract), "UsualDAO Bond 121", "USD0PP121", block.timestamp
        );
        usd0PP.initializeV1();
        usd0PP.initializeV2();
    }

    function testCreateUsd0PPFailIfIncorrect() public {
        vm.warp(10);

        Usd0PPHarness usd0PPbefore = new Usd0PPHarness();
        _resetInitializerImplementation(address(usd0PPbefore));
        // begin in past
        vm.expectRevert(abi.encodeWithSelector(BeginInPast.selector));
        vm.prank(admin);
        usd0PPbefore.initialize(address(registryContract), "UsualDAO Bond", "USD0PP", 9);

        Usd0PPHarness lsausUSbadName = new Usd0PPHarness();
        _resetInitializerImplementation(address(lsausUSbadName));
        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        vm.prank(admin);
        lsausUSbadName.initialize(address(registryContract), "", "USD0PP", block.timestamp);

        Usd0PPHarness lsausUSbadSymbol = new Usd0PPHarness();
        _resetInitializerImplementation(address(lsausUSbadSymbol));
        vm.expectRevert(abi.encodeWithSelector(InvalidSymbol.selector));
        vm.prank(admin);
        lsausUSbadSymbol.initialize(address(registryContract), "USD0PP", "", block.timestamp);
    }

    function testMintUsd0PP(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        skip(3650 days);
        usd0PP100.unwrap();
        assertEq(stbcToken.balanceOf(address(alice)), amount);
        vm.stopPrank();
    }

    function testMintWithPermitUsd0PP(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );

        usd0PP100.mintWithPermit(amount, deadline, v, r, s);
        skip(3650 days);
        usd0PP100.unwrap();
        assertEq(stbcToken.balanceOf(address(alice)), amount);
        vm.stopPrank();
    }

    function testMintWithPermitUsd0PPFailingERC20Permit(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0

        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );
        // deadline in the past
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, s);
        deadline = block.timestamp + 100;
        // insufficient amount
        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount - 1, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, s);
        // bad v
        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );

        usd0PP100.mintWithPermit(amount, deadline, v + 1, r, s);
        // bad r
        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );

        usd0PP100.mintWithPermit(amount, deadline, v, keccak256("bad r"), s);

        // bad s
        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, keccak256("bad s"));

        //bad nonce
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            alice,
            alicePrivKey,
            address(usd0PP100),
            amount,
            deadline,
            IERC20Permit(address(stbcToken)).nonces(alice) + 1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, s);

        //bad spender
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(usd0PP100),
            amount,
            deadline,
            IERC20Permit(address(stbcToken)).nonces(bob)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP100), 0, amount
            )
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, s);
        // this should work
        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount, deadline
        );
        usd0PP100.mintWithPermit(amount, deadline, v, r, s);
        skip(3650 days);
        usd0PP100.unwrap();
        assertEq(stbcToken.balanceOf(address(alice)), amount);

        vm.stopPrank();
    }

    function testMintShouldWorkUntilTheEnd(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);
        vm.warp(usd0PP100.getEndTime() - 1);
        usd0PP100.mint(amount / 2);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), amount / 2);
        vm.expectRevert(abi.encodeWithSelector(BondNotFinished.selector));
        usd0PP100.unwrap();
        vm.warp(usd0PP100.getEndTime());
        vm.expectRevert(abi.encodeWithSelector(BondFinished.selector));
        usd0PP100.mint(amount / 2);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), amount / 2);
        usd0PP100.unwrap();
        vm.stopPrank();
    }

    function testMintShouldWorkBeforeTheEndForPegMaintainerRole(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        vm.startPrank(address(admin));
        registryAccess.grantRole(PEG_MAINTAINER_UNLIMITED_ROLE, alice);
        vm.stopPrank();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);
        vm.warp(usd0PP100.getEndTime() - 1);
        usd0PP100.mint(amount / 2);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), amount / 2);
        usd0PP100.unwrapPegMaintainer(amount / 2);
        assertEq(stbcToken.balanceOf(address(alice)), amount);
        vm.stopPrank();
    }

    function testUnwrapPegMaintainerRevertsIfBondNotStarted() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(PEG_MAINTAINER_UNLIMITED_ROLE, alice);
        vm.stopPrank();

        Usd0PPHarness usd0PP100 = new Usd0PPHarness();
        _resetInitializerImplementation(address(usd0PP100));
        usd0PP100.initialize(address(registryContract), "UsualDAO Bond 100", "USD0PP A100", 10 days);
        usd0PP100.initializeV1();

        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(BondNotStarted.selector));
        usd0PP100.unwrapPegMaintainer(10);
    }

    function testUnwrapPegMaintainerRevertsIfNotEnoughBalance() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(PEG_MAINTAINER_UNLIMITED_ROLE, alice);
        vm.stopPrank();

        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usd0PP100.unwrapPegMaintainer(1000);
    }

    function testTriggerPARMechanismCurvepoolShouldFailIfAmountIsZero() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(PEG_MAINTAINER_ROLE, alice);
        vm.stopPrank();

        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.startPrank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP100.triggerPARMechanismCurvepool(0, 1);

        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP100.triggerPARMechanismCurvepool(1, 0);
    }

    function testMintWithPermitShouldWorkUntilTheEnd(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0

        uint256 deadline = type(uint256).max;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount / 2, deadline
        );

        vm.warp(usd0PP100.getEndTime() - 1);
        usd0PP100.mintWithPermit(amount / 2, deadline, v, r, s);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), amount / 2);
        vm.expectRevert(abi.encodeWithSelector(BondNotFinished.selector));
        usd0PP100.unwrap();
        vm.warp(usd0PP100.getEndTime());

        (v, r, s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount / 2, deadline
        );
        vm.expectRevert(abi.encodeWithSelector(BondFinished.selector));
        usd0PP100.mintWithPermit(amount / 2, deadline, v, r, s);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), amount / 2);
        usd0PP100.unwrap();
        vm.stopPrank();
    }

    function testMintBeforeBondStartShouldFail(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);
        vm.warp(block.timestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(BondNotStarted.selector));
        usd0PP100.mint(amount);
        vm.stopPrank();
    }

    function testMintTwiceAndTransferUsd0PP(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral
        stbcToken.approve(address(usd0PP100), amount);
        // divide amount
        uint256 fourthAmount = amount / 4;
        uint256 halfAmount = amount / 2;
        usd0PP100.mint(fourthAmount);
        skip(1 days);
        usd0PP100.mint(halfAmount);
        skip(10 days); // 11days since beginning
        // transfer 1/4 of the amount
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), (halfAmount + fourthAmount));
        usd0PP100.transfer(address(bob), fourthAmount);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), (halfAmount));
        // bob paid no fee
        assertEq(IERC20(address(usd0PP100)).balanceOf(treasury), 0);
        uint256 bobBalance1 = fourthAmount;
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), bobBalance1);
        skip(10 days); // 21 days since beginning
        usd0PP100.transfer(address(bob), halfAmount);
        // bob gets less because of the fee

        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), (0));
        assertEq(IERC20(address(usd0PP100)).balanceOf(treasury), 0);
        uint256 bobBalance2 = halfAmount;
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), bobBalance1 + bobBalance2);
        // alice still has some pending rewards as she has half of the amount for  days after her last claim
        skip(10 days); // 31 days since beginning
        usd0PP100.mint(fourthAmount);
        skip(20 days); // 51 days since beginning
        vm.stopPrank();
        skip(20 days); // 71 days since beginning
        vm.prank(bob);
        IERC20(usd0PP100).approve(jack, bobBalance1);
        vm.prank(jack);
        usd0PP100.transferFrom(address(bob), address(jack), bobBalance1);

        uint256 jackBalance = bobBalance1;
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), bobBalance2);
        assertEq(IERC20(usd0PP100).balanceOf(address(jack)), jackBalance);
        vm.warp(usd0PP100.getEndTime()); // 99 days since beginning + 1 second
        vm.prank(alice);
        usd0PP100.unwrap();
        assertApproxEqAbs(stbcToken.balanceOf(address(alice)), fourthAmount, 1_000_000);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), 0);
        vm.prank(bob);
        usd0PP100.unwrap();
        assertApproxEqAbs(stbcToken.balanceOf(address(bob)), bobBalance2, 1_000_000);
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), 0);
        vm.prank(jack);
        usd0PP100.unwrap();
        assertApproxEqAbs(stbcToken.balanceOf(address(jack)), jackBalance, 1_000_000);
        assertEq(IERC20(usd0PP100).balanceOf(address(jack)), 0);
        assertEq(IERC20(usd0PP100).totalSupply(), 0);
    }

    // can't mint 1 day before end
    // test minting right before end should revert
    function testMintShouldNotFailOneSecondBeforeTheEnd() public {
        uint256 amount = 1000 ether;
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount / 2);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);

        // divide amount
        skip(98 days);
        usd0PP100.mint(amount / 2);
        vm.warp(usd0PP100.getEndTime() - 1);
        IERC20(usd0PP100).transfer(bob, amount / 2);
        vm.stopPrank();
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(bob), amount - amount / 2);
        vm.startPrank(address(bob));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount - amount / 2);
        skip(usd0PP100.getEndTime() + 1);

        usd0PP100.unwrap();
        assertEq(stbcToken.balanceOf(address(bob)), amount);
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), 0);
        vm.stopPrank();
        // alice can unwrap
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), 0);
        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP100.unwrap();
    }

    function testUnwrapPegMaintainer_RevertsIfInsufficientBalance(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        vm.startPrank(address(admin));
        registryAccess.grantRole(PEG_MAINTAINER_UNLIMITED_ROLE, alice);
        vm.stopPrank();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        skip(10 days);
        vm.prank(address(alice));

        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usd0PP100.unwrapPegMaintainer(amount + 1);
    }

    // can't mint 1 day before end
    // test minting right before end should revert
    function testMintWithPermitShouldNotFailOneSecondBeforeTheEnd() public {
        uint256 amount = 1000 ether;
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount / 2);
        vm.startPrank(address(alice));
        // swap for USD0

        uint256 deadline = type(uint256).max;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken), alice, alicePrivKey, address(usd0PP100), amount / 2, deadline
        );

        // divide amount
        skip(98 days);
        usd0PP100.mintWithPermit(amount / 2, deadline, v, r, s);
        vm.warp(usd0PP100.getEndTime() - 1);
        IERC20(usd0PP100).transfer(bob, amount / 2);
        vm.stopPrank();
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(bob), amount / 2);

        (v, r, s) = _getSelfPermitData(
            address(stbcToken), bob, bobPrivKey, address(usd0PP100), amount / 2, deadline
        );
        vm.startPrank(address(bob));
        usd0PP100.mintWithPermit(amount / 2, deadline, v, r, s);
        skip(usd0PP100.getEndTime() + 1);

        usd0PP100.unwrap();
        assertEq(stbcToken.balanceOf(address(bob)), amount);
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), 0);
        vm.stopPrank();
        // alice can unwrap
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), 0);
        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP100.unwrap();
    }

    function testConsecutiveMints() public {
        uint256 amount = 1_000_000 ether;
        _createRwa();
        // 10% over 100 days for 1000 USD0 max
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP100), amount);
        // divide amount
        uint256 fourthAmount = amount / 4;
        uint256 halfAmount = amount / 2;
        usd0PP100.mint(fourthAmount);

        skip(1 days + 3600);
        usd0PP100.mint(fourthAmount);
        skip(3600 * 22);
        usd0PP100.mint(fourthAmount);
        skip(10 days + 3599); // 11days since beginning only 1sec until 12days

        skip(1 days + 3600); // 12 days + 1 hour
        usd0PP100.transfer(address(bob), fourthAmount);
        usd0PP100.mint(fourthAmount);
        vm.stopPrank();
        skip(3600);
        skip(3600);
        vm.prank(bob);
        usd0PP100.transfer(address(alice), fourthAmount);
        skip(3600);

        skip(3600 * 20); // 13 days

        vm.prank(alice);
        usd0PP100.transfer(address(bob), halfAmount);
        skip((3600 * 9) - 1); // 14 days - 1sec
        uint256 blockNum = block.timestamp;
        skip(1);
        // if less than 12sec passed since the last block then no new block
        assertEq(block.timestamp, blockNum + 1);

        skip(12);
        assertEq(block.timestamp, blockNum + 13);

        blockNum = block.timestamp;
        skip(usd0PP100.getEndTime());
        vm.prank(bob);
        usd0PP100.unwrap();
        vm.prank(alice);
        usd0PP100.unwrap();
        assertApproxEqAbs(stbcToken.balanceOf(address(alice)), halfAmount, 1_000_000);
        assertApproxEqAbs(stbcToken.balanceOf(address(bob)), halfAmount, 1_000_000);
        assertEq(IERC20(usd0PP100).balanceOf(address(alice)), 0);
        assertEq(IERC20(usd0PP100).balanceOf(address(bob)), 0);
    }

    function testTransferFrom1(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);
        _createRwa();
        Usd0PP usd0PP180 = _createBond("UsualDAO Bond 180", "USD0PP A0");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        amount = amount / 2;
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP180), amount);
        usd0PP180.mint(amount);
        assertEq(stbcToken.balanceOf(address(usd0PP180)), amount);
        skip(10 days);
        // 10 days after minting
        IERC20(usd0PP180).approve(bob, amount / 2);
        vm.stopPrank();

        vm.prank(bob);
        IERC20(usd0PP180).transferFrom(alice, bob, amount / 2);

        uint256 bobBalance = amount / 2;
        assertEq(IERC20(usd0PP180).balanceOf(address(bob)), bobBalance);
    }

    function testTransferFromShouldFailIfBlacklisted() public {
        uint256 amount = 100_000_000_000;
        _createRwa();
        Usd0PP usd0PP180 = _createBond("UsualDAO Bond 180", "USD0PP A0");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        amount = amount / 2;
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP180), amount);
        usd0PP180.mint(amount);
        assertEq(stbcToken.balanceOf(address(usd0PP180)), amount);
        skip(10 days);
        // 10 days after minting
        IERC20(usd0PP180).approve(bob, amount / 2);
        vm.stopPrank();

        vm.prank(blacklistOperator);
        stbcToken.blacklist(address(alice));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        IERC20(usd0PP180).transferFrom(alice, bob, amount / 2);

        vm.startPrank(blacklistOperator);
        stbcToken.unBlacklist(address(alice));
        stbcToken.blacklist(address(bob));
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        IERC20(usd0PP180).transferFrom(alice, bob, amount / 2);
    }

    function testTransferFromShouldNotFailAllowListDisabled() public {
        uint256 amount = 100_000_000_000;
        _createRwa();
        Usd0PP usd0PP180 = _createBond("UsualDAO Bond 180", "USD0PP A0");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        amount = amount / 2;
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral

        stbcToken.approve(address(usd0PP180), amount);
        usd0PP180.mint(amount);
        assertEq(stbcToken.balanceOf(address(usd0PP180)), amount);
        skip(10 days);
        // 10 days after minting
        IERC20(usd0PP180).approve(bob, amount);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(usd0PP180).approve(bob, amount);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, bob));
        IERC20(usd0PP180).transferFrom(alice, bob, amount / 2);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, bob));
        IERC20(usd0PP180).transferFrom(bob, alice, amount / 2);
    }

    function testTransferShouldFailIfNullAddress() public {
        testTransferFrom1(100e18);
        // get bond with symbol USD0PP A0
        IUsd0PP usd0PP180 = IUsd0PP(registryContract.getContract(CONTRACT_USD0PP));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        usd0PP180.transfer(address(0), 1);
    }

    function testTransferShouldFailIfZeroAmount() public {
        testTransferFrom1(100e18);
        // get bond with symbol USD0PP A0
        IUsd0PP usd0PP180 = IUsd0PP(registryContract.getContract(CONTRACT_USD0PP));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP180.transfer(bob, 0);
    }

    function testTransferShouldFailIfMoreThanBalance() public {
        testTransferFrom1(100e18);

        // get bond with symbol USD0PP A0
        IUsd0PP usd0PP180 = IUsd0PP(registryContract.getContract(CONTRACT_USD0PP));

        uint256 aliceBalanceBefore = IERC20(address(usd0PP180)).balanceOf(address(alice));
        uint256 bobBalanceBefore = IERC20(address(usd0PP180)).balanceOf(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                aliceBalanceBefore,
                aliceBalanceBefore + 1
            )
        );
        vm.prank(alice);
        usd0PP180.transfer(bob, aliceBalanceBefore + 1);
        uint256 aliceBalanceAfter = IERC20(address(usd0PP180)).balanceOf(address(alice));
        uint256 bobBalanceAfter = IERC20(address(usd0PP180)).balanceOf(address(bob));
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
        assertEq(bobBalanceAfter, bobBalanceBefore);
    }

    function testTransferFromShouldFailIfZeroAmount() public {
        testTransferFrom1(100e18);
        // get bond with symbol USD0PP A0
        IERC20 usd0PP180 = IERC20(registryContract.getContract(CONTRACT_USD0PP));
        uint256 aliceBalanceBefore = usd0PP180.balanceOf(address(alice));
        vm.prank(alice);
        usd0PP180.approve(bob, aliceBalanceBefore);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        vm.prank(bob);
        usd0PP180.transferFrom(alice, bob, 0);
    }

    function testTransferFromShouldFailIfMoreThanAllow() public {
        testTransferFrom1(100e18);
        // get bond with symbol USD0PP A0
        IERC20 usd0PP180 = IERC20(registryContract.getContract(CONTRACT_USD0PP));

        uint256 aliceBalanceBefore = usd0PP180.balanceOf(address(alice));
        uint256 bobBalanceBefore = usd0PP180.balanceOf(address(bob));
        vm.prank(alice);
        usd0PP180.approve(bob, aliceBalanceBefore - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                bob,
                bobBalanceBefore - 1,
                bobBalanceBefore
            )
        );
        vm.prank(bob);
        usd0PP180.transferFrom(alice, bob, aliceBalanceBefore);
        uint256 aliceBalanceAfter = usd0PP180.balanceOf(address(alice));
        uint256 bobBalanceAfter = usd0PP180.balanceOf(address(bob));
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
        assertEq(bobBalanceAfter, bobBalanceBefore);
    }

    function testTransferFromShouldFailIfMoreThanBalance() public {
        testTransferFrom1(100e18);
        // get bond with symbol USD0PP A0
        IERC20 usd0PP180 = IERC20(registryContract.getContract(CONTRACT_USD0PP));

        uint256 aliceBalanceBefore = usd0PP180.balanceOf(address(alice));
        uint256 bobBalanceBefore = usd0PP180.balanceOf(address(bob));
        vm.prank(alice);
        usd0PP180.approve(bob, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                aliceBalanceBefore,
                aliceBalanceBefore * 2
            )
        );
        vm.prank(bob);
        usd0PP180.transferFrom(alice, bob, aliceBalanceBefore * 2);
        uint256 aliceBalanceAfter = usd0PP180.balanceOf(address(alice));
        uint256 bobBalanceAfter = usd0PP180.balanceOf(address(bob));
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
        assertEq(bobBalanceAfter, bobBalanceBefore);
    }

    function testMintUsd0PPShouldFailAfterEndDate() public {
        uint256 amount = 1e18;
        testTransferFrom1(amount);
        IUsd0PP usd0PP180 = IUsd0PP(registryContract.getContract(CONTRACT_USD0PP));
        uint256 aliceBalance = IERC20(address(usd0PP180)).balanceOf(address(alice));
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        //   end block
        skip(usd0PP180.getEndTime() + 1);
        vm.expectRevert(abi.encodeWithSelector(BondFinished.selector));
        usd0PP180.mint(amount * 100);
        assertEq(IERC20(address(usd0PP180)).balanceOf(address(alice)), aliceBalance);
        vm.stopPrank();
    }

    function testCreateUsd0PPShouldWork() public {
        Usd0PP bond = _createBond("UsualDAO Bond 121", "USD0PP lsUSD");

        assertEq(bond.name(), "UsualDAO Bond 121");
        assertEq(bond.symbol(), "USD0PP lsUSD");
        assertEq(bond.decimals(), 18);
        assertEq(bond.getStartTime(), block.timestamp);
        assertEq(bond.getEndTime(), block.timestamp + BOND_DURATION_FOUR_YEAR);
        assertEq(bond.totalBondTimes(), BOND_DURATION_FOUR_YEAR);
    }

    function testEmergencyWithdraw() public {
        uint256 amount = 100e18;
        testTransferFrom1(amount);
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        assertEq(stbcToken.balanceOf(bob), 0);
        uint256 bal = stbcToken.balanceOf(address(usd0PP180));
        assertGt(bal, 0);
        vm.prank(admin);
        usd0PP180.emergencyWithdraw(bob);
        assertEq(stbcToken.balanceOf(bob), bal);
    }

    function testEmergencyWithdrawShouldWorkIfPaused() public {
        uint256 amount = 100e18;
        testTransferFrom1(amount);
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        assertEq(stbcToken.balanceOf(bob), 0);
        uint256 bal = stbcToken.balanceOf(address(usd0PP180));
        assertGt(bal, 0);
        vm.prank(pauser);
        usd0PP180.pause();
        vm.prank(admin);
        usd0PP180.emergencyWithdraw(bob);

        assertEq(usd0PP180.paused(), true);
        assertEq(stbcToken.balanceOf(bob), bal);
    }

    function testEmergencyWithdrawFailIfNullAddress() public {
        uint256 amount = 100e18;
        testTransferFrom1(amount);
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        vm.expectRevert();
        vm.prank(admin);
        usd0PP180.emergencyWithdraw(address(0));
    }

    function testEmergencyWithdrawFailIfNotAuthorized() public {
        uint256 amount = 100e18;
        testTransferFrom1(amount);
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP180.emergencyWithdraw(address(0));
    }

    function testCannotMintAfterEmergencyWithdraw() public {
        uint256 amount = 100e18;
        testTransferFrom1(amount);
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        assertEq(stbcToken.balanceOf(bob), 0);
        uint256 bal = stbcToken.balanceOf(address(usd0PP180));
        assertGt(bal, 0);
        vm.prank(admin);
        usd0PP180.emergencyWithdraw(bob);

        vm.prank(address(daoCollateral));
        stbcToken.mint(address(bob), amount);

        vm.startPrank(bob);
        stbcToken.approve(address(usd0PP180), amount * 2);
        vm.expectRevert();
        usd0PP180.mint(amount);
        vm.stopPrank();

        vm.prank(admin);
        usd0PP180.unpause();

        vm.prank(bob);
        usd0PP180.mint(amount);
        assertGt(IERC20(address(usd0PP180)).balanceOf(address(bob)), amount);
    }

    function testTemporaryRedemptionAllocationWorks() public {
        //@arrange
        uint256 amount = 100e18;
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        vm.stopPrank();
        uint256 temporaryUnlockStartTime = usd0PP100.getTemporaryUnlockStartTime();
        uint256 temporaryUnlockEndTime = usd0PP100.getTemporaryUnlockEndTime();

        //@act
        uint256 allocatedRedemptionAmount = usd0PP100.getAllocationEarlyUnlock(address(alice));

        //@assert
        assertEq(allocatedRedemptionAmount, amount);
        assertEq(temporaryUnlockStartTime, earlyUnlockStart);
        assertEq(temporaryUnlockEndTime, earlyUnlockStop);
    }

    function testTemporaryRedemptionAllocationWorksFuzz(uint256 amount, address userToFuzz)
        public
    {
        //@arrange
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(address(0) != userToFuzz);
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(userToFuzz, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(userToFuzz);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        //@act
        uint256 allocatedRedemptionAmount = usd0PP100.getAllocationEarlyUnlock(address(userToFuzz));

        //@assert
        assertEq(allocatedRedemptionAmount, amount);
    }

    function testAllocateEarlyUnlockBalanceShouldEmitEvent() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        vm.expectEmit();
        emit EarlyUnlockBalancesSet(redemptionAddressesToAllocateTo, redemptionAmountsToAllocate);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
    }

    function testTemporaryRedemptionAllocation_revertsIfInvalidInputs(
        uint256 amount,
        address userToFuzz
    ) public {
        //@arrange
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(address(0) != userToFuzz);
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(userToFuzz, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](2);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(userToFuzz);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);

        //@act
        //@assert
        vm.expectRevert(InvalidInputArraysLength.selector);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
    }

    function testTemporaryRedemptionAllocation_revertsIfNullAddress() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(0);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);

        vm.expectRevert(NullAddress.selector);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
    }

    function testTemporaryRedemptionAllocationClaimableFuzz(uint256 amount, address userToFuzz)
        public
    {
        //@arrange
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(address(0) != userToFuzz);
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(userToFuzz, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(userToFuzz);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();
        uint256 balanceBeforeExitUnwrap = stbcToken.balanceOf(address(userToFuzz));
        assertEq(balanceBeforeExitUnwrap, 0);

        //@act
        vm.prank(userToFuzz);
        usd0PP100.temporaryOneToOneExitUnwrap(amount);

        //@assert
        uint256 balanceAfterExitUnwrap = stbcToken.balanceOf(address(userToFuzz));
        assertEq(balanceAfterExitUnwrap, amount);
    }

    function testTemporaryRedemptionAllocationClaiming_RevertsOutsideUnlockPeriod() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        skip(1 days);
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        //@act
        //@assert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OutsideEarlyUnlockTimeframe.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
    }

    function testTemporaryRedemptionAllocationClaiming_RevertsWithoutAllocation() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        vm.stopPrank();

        //@act
        //@assert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotPermittedToEarlyUnlock.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
    }

    function testTemporaryRedemptionAllocationClaiming_RevertsWithoutSufficientUsd0ppBalance()
        public
    {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, 1);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        //@act
        //@assert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
    }

    function testSetupEarlyUnlockPeriod_RevertsIfOutOfBounds() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp;
        uint256 earlyUnlockStop = END_OF_EARLY_UNLOCK_PERIOD + 1;
        vm.expectRevert(abi.encodeWithSelector(OutOfBounds.selector));
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
    }

    function testSetupEarlyUnlockPeriodShouldEmitEvent() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp;
        uint256 earlyUnlockStop = END_OF_EARLY_UNLOCK_PERIOD;
        vm.expectEmit();
        emit EarlyUnlockPeriodSet(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
    }

    function testTemporaryRedemptionAllocationClaiming_RevertsIfUserIsDisabled() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);

        // Grant EARLY_BOND_UNLOCK_ROLE to admin and set up early unlock period
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        // Disable alice's temporary redemptions
        vm.startPrank(registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));
        address[] memory addressesToDisableRedemptionsFor = new address[](1);
        addressesToDisableRedemptionsFor[0] = alice;
        bool[] memory rightsToRedeemTemporarily = new bool[](1);
        rightsToRedeemTemporarily[0] = true;
        usd0PP100.setBondEarlyUnlockDisabled(addressesToDisableRedemptionsFor[0]);
        vm.stopPrank();

        //@act
        // Alice tries to perform the temporary one-to-one exit unwrap
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);

        //@assert
        // Ensure that alice's USD0PP balance remains unchanged
        uint256 aliceUsd0ppBalance = usd0PP100.balanceOf(alice);
        assertEq(aliceUsd0ppBalance, amount);
    }

    function testSeveralTemporaryRedemptionAllocationClaiming_RevertsIfUserIsDisabled() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        vm.startPrank(address(daoCollateral));
        stbcToken.mint(address(bob), amount);
        stbcToken.mint(address(carol), amount);
        vm.stopPrank();

        vm.startPrank(address(bob));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        vm.stopPrank();

        vm.startPrank(address(carol));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        vm.stopPrank();

        uint256[] memory redemptionAmountsToAllocate = new uint256[](3);
        address[] memory redemptionAddressesToAllocateTo = new address[](3);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        redemptionAmountsToAllocate[1] = amount;
        redemptionAddressesToAllocateTo[1] = address(bob);
        redemptionAmountsToAllocate[2] = amount;
        redemptionAddressesToAllocateTo[2] = address(carol);

        // Grant EARLY_BOND_UNLOCK_ROLE to admin and set up early unlock period
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = block.timestamp + 1;
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        // Disable alice's temporary redemptions
        vm.startPrank(registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));
        usd0PP100.setBondEarlyUnlockDisabled(alice);
        usd0PP100.setBondEarlyUnlockDisabled(carol);
        vm.stopPrank();

        //@act
        // Alice tries to perform the temporary one-to-one exit unwrap
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
        //@assert
        // Ensure that alice's USD0PP balance remains unchanged
        uint256 aliceUsd0ppBalance = usd0PP100.balanceOf(alice);
        assertEq(aliceUsd0ppBalance, amount);
        // carol tries to perform the temporary one-to-one exit unwrap
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
        //@assert
        // Ensure that carol's USD0PP balance remains unchanged
        uint256 carolUsd0ppBalance = usd0PP100.balanceOf(carol);
        assertEq(carolUsd0ppBalance, amount);

        // bob can perform the temporary one-to-one exit unwrap
        vm.prank(bob);
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
        //@assert
        // Ensure that bob's USD0PP balance updates
        uint256 bobUsd0ppBalance = usd0PP100.balanceOf(bob);
        assertEq(bobUsd0ppBalance, 0);
    }

    function testDisableUserTemporaryRedemptions_WorksAsExpected() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        address userToDisable = alice;
        bool rightsToRedeemTemp = true;

        // Grant the CONTRACT_AIRDROP_TAX_COLLECTOR role to the admin
        vm.startPrank(admin);
        registryAccess.grantRole(CONTRACT_AIRDROP_TAX_COLLECTOR, admin);
        vm.stopPrank();

        //@act
        vm.startPrank(registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));
        address[] memory addressesToDisableRedemptionsFor = new address[](1);
        addressesToDisableRedemptionsFor[0] = userToDisable;
        bool[] memory rightsToRedeemTemporarily = new bool[](1);
        rightsToRedeemTemporarily[0] = rightsToRedeemTemp;

        vm.expectEmit();
        emit BondEarlyUnlockDisabled(userToDisable);
        usd0PP100.setBondEarlyUnlockDisabled(addressesToDisableRedemptionsFor[0]);
        vm.stopPrank();

        //@assert
        bool isDisabled = usd0PP100.getBondEarlyUnlockDisabled(userToDisable);
        assertEq(isDisabled, rightsToRedeemTemp);
    }

    function testDisableUserTemporaryRedemptions_RevertsIfCallerNotAuthorized() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        address userToDisable = alice;
        bool rightsToRedeemTemp = true;

        //@act @assert
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        address[] memory addressesToDisableRedemptionsFor = new address[](1);
        addressesToDisableRedemptionsFor[0] = userToDisable;
        bool[] memory rightsToRedeemTemporarily = new bool[](1);
        rightsToRedeemTemporarily[0] = rightsToRedeemTemp;

        usd0PP100.setBondEarlyUnlockDisabled(addressesToDisableRedemptionsFor[0]);
    }

    function testDisableUserTemporaryRedemptions_RevertsWhenPaused() public {
        //@arrange
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        address userToDisable = alice;
        bool rightsToRedeemTemp = true;

        // Grant the CONTRACT_AIRDROP_TAX_COLLECTOR role to the admin and pause the contract
        vm.startPrank(admin);
        registryAccess.grantRole(CONTRACT_AIRDROP_TAX_COLLECTOR, admin);
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, admin);
        usd0PP100.pause();
        vm.stopPrank();
        address[] memory addressesToDisableRedemptionsFor = new address[](1);
        addressesToDisableRedemptionsFor[0] = userToDisable;
        bool[] memory rightsToRedeemTemporarily = new bool[](1);
        rightsToRedeemTemporarily[0] = rightsToRedeemTemp;
        //@act
        // Try to call the function while the contract is paused
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usd0PP100.setBondEarlyUnlockDisabled(addressesToDisableRedemptionsFor[0]);
    }

    function testUnpause() public {
        Usd0PP usd0PP180 = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP180.pause();

        vm.prank(pauser);
        usd0PP180.pause();

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP180.unpause();

        vm.prank(admin);
        usd0PP180.unpause();
    }

    function testUpdateFloorPrice() public {
        Usd0PP usd0PP = _createBond("UsualDAO Bond", "USD0PP");

        uint256 newFloorPrice = 860_000_000_000_000_000; // 0.86
        vm.prank(floorPriceUpdater);
        usd0PP.updateFloorPrice(newFloorPrice);

        assertEq(usd0PP.getFloorPrice(), newFloorPrice);
    }

    function testUpdateFloorPriceFailsIfNotAdmin() public {
        Usd0PP usd0PP = _createBond("UsualDAO Bond", "USD0PP");

        uint256 newFloorPrice = 860_000_000_000_000_000; // 0.86
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.updateFloorPrice(newFloorPrice);
    }

    function testUpdateFloorPriceFailsIfTooHigh() public {
        Usd0PP usd0PP = _createBond("UsualDAO Bond", "USD0PP");

        uint256 newFloorPrice = 1_000_000_000_000_000_001; // 1.000000000000000001
        vm.expectRevert(abi.encodeWithSelector(FloorPriceTooHigh.selector));
        usd0PP.updateFloorPrice(newFloorPrice);
        vm.stopPrank();
    }

    function testunlockUsd0ppFloorPriceFailIfFloorPriceNotSet() public {
        uint256 amount = 100e18;
        _createRwa();
        vm.startPrank(address(admin));
        Usd0PPHarness usd0PP100 = new Usd0PPHarness();
        _resetInitializerImplementation(address(usd0PP100));
        usd0PP100.initialize(
            address(registryContract), "UsualDAO Bond 100", "USD0PP A100", block.timestamp
        );
        //usd0PP100.initializeV1(); // We avoid the setting of the floor price by not calling initializeV1
        vm.stopPrank();

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(FloorPriceNotSet.selector));
        usd0PP100.unlockUsd0ppFloorPrice(amount);
        vm.stopPrank();
    }

    function testunlockUsd0ppFloorPrice() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        _resetInitializerImplementation(address(usd0PP100));
        usd0PP100.initializeV2();

        uint256 treasuryBalanceBefore = stbcToken.balanceOf(treasuryYield);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Usd0ppUnlockedFloorPrice(alice, amount, (amount * usd0PP100.getFloorPrice()) / 1e18);
        usd0PP100.unlockUsd0ppFloorPrice(amount);
        vm.stopPrank();

        uint256 expectedUsd0Amount = (amount * usd0PP100.getFloorPrice()) / 1e18;
        assertEq(stbcToken.balanceOf(address(alice)), expectedUsd0Amount);
        assertEq(usd0PP100.balanceOf(address(alice)), 0);

        uint256 expectedDelta = amount - expectedUsd0Amount;
        assertEq(stbcToken.balanceOf(treasuryYield), treasuryBalanceBefore + expectedDelta);
    }

    function testunlockUsd0ppFloorPriceWithDifferentFloorPrices() public {
        uint256 amount = 1000e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        _resetInitializerImplementation(address(usd0PP100));
        usd0PP100.initializeV2();

        uint256 treasuryBalanceBefore = stbcToken.balanceOf(treasuryYield);

        // Test with initial floor price
        vm.startPrank(alice);
        usd0PP100.unlockUsd0ppFloorPrice(500e18);
        vm.stopPrank();

        uint256 expectedUsd0Amount1 = (500e18 * usd0PP100.getFloorPrice()) / 1e18;
        uint256 expectedDelta1 = 500e18 - expectedUsd0Amount1;
        assertEq(stbcToken.balanceOf(address(alice)), expectedUsd0Amount1);
        assertEq(stbcToken.balanceOf(treasuryYield), treasuryBalanceBefore + expectedDelta1);

        // Update floor price and test again
        vm.startPrank(floorPriceUpdater);
        usd0PP100.updateFloorPrice(900_000_000_000_000_000); // 0.9
        vm.stopPrank();

        vm.startPrank(alice);
        usd0PP100.unlockUsd0ppFloorPrice(500e18);
        vm.stopPrank();

        uint256 expectedUsd0Amount2 = (500e18 * usd0PP100.getFloorPrice()) / 1e18;
        uint256 expectedDelta2 = 500e18 - expectedUsd0Amount2;
        assertEq(stbcToken.balanceOf(address(alice)), expectedUsd0Amount1 + expectedUsd0Amount2);
        assertEq(
            stbcToken.balanceOf(treasuryYield),
            treasuryBalanceBefore + expectedDelta1 + expectedDelta2
        );
    }

    function testFuzzUnlockUsd0ppFloorPrice(uint256 amount, uint256 floorPrice) public {
        amount = bound(amount, 1, 1_000_000e18);
        floorPrice = bound(floorPrice, 1, 1e18); //@note, this is intentional. If the floor price is set to 0, we cannot use the function as intended
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);
        vm.startPrank(floorPriceUpdater);
        usd0PP100.updateFloorPrice(floorPrice);
        vm.stopPrank();

        uint256 treasuryBalanceBefore = stbcToken.balanceOf(treasuryYield);
        uint256 aliceBalanceBefore = stbcToken.balanceOf(address(alice));

        vm.startPrank(alice);
        usd0PP100.unlockUsd0ppFloorPrice(amount);
        vm.stopPrank();

        uint256 expectedUsd0Amount = (amount * floorPrice) / 1e18;
        uint256 expectedDelta = amount - expectedUsd0Amount;

        assertEq(stbcToken.balanceOf(address(alice)), aliceBalanceBefore + expectedUsd0Amount);
        assertEq(usd0PP100.balanceOf(address(alice)), 0);
        assertEq(stbcToken.balanceOf(treasuryYield), treasuryBalanceBefore + expectedDelta);
    }

    function testunlockUsd0ppFloorPriceWithZeroDelta() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(floorPriceUpdater);
        usd0PP100.updateFloorPrice(1e18); // Set floor price to 1
        vm.stopPrank();

        uint256 treasuryBalanceBefore = stbcToken.balanceOf(treasuryYield);

        vm.startPrank(alice);
        usd0PP100.unlockUsd0ppFloorPrice(amount);
        vm.stopPrank();

        assertEq(stbcToken.balanceOf(address(alice)), amount);
        assertEq(usd0PP100.balanceOf(address(alice)), 0);
        assertEq(stbcToken.balanceOf(treasuryYield), treasuryBalanceBefore); // No change in treasury balance
    }

    function testunlockUsd0ppFloorPriceFailsIfInsufficientBalance() public {
        uint256 amount = 1000 ether;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InsufficientUsd0ppBalance.selector));
        usd0PP100.unlockUsd0ppFloorPrice(amount + 1 ether);
        vm.stopPrank();
    }

    function testunlockUsd0ppFloorPriceFailsIfZeroAmount() public {
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, 100e18);

        vm.expectRevert(abi.encodeWithSelector(AmountMustBeGreaterThanZero.selector));
        usd0PP100.unlockUsd0ppFloorPrice(0);
    }

    function testunlockUsd0ppFloorPriceFailsIfPaused() public {
        uint256 amount = 1000 ether;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.prank(pauser);
        usd0PP100.pause();

        scaffoldUsd0ppMintUser(address(alice), amount);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usd0PP100.unlockUsd0ppFloorPrice(amount);
        vm.stopPrank();
    }

    function scaffoldUsd0ppMintUser(address user, uint256 amount) public returns (Usd0PP) {
        _createRwa();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.stopPrank();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(user), amount);
        vm.startPrank(address(user));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        vm.stopPrank();

        return usd0PP100;
    }

    function testSetBondEarlyUnlockDisabledRevertIfNotAuthorized() public {
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP100.setBondEarlyUnlockDisabled(address(alice));
    }

    function testSetUnwrapCap_RevertsIfNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.setUnwrapCap(alice, 1000e18);
    }

    function testSetUnwrapCap() public {
        uint256 cap = 1000e18;

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit UnwrapCapSet(alice, cap);
        usd0PP.setUnwrapCap(alice, cap);

        assertEq(usd0PP.getUnwrapCap(alice), cap);
        vm.stopPrank();
    }

    function testUnwrapWithCap() public {
        uint256 amount = 100e18;
        uint256 cap = 1000e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        uint256 initialBalance = stbcToken.balanceOf(alice);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CappedUnwrap(alice, amount, cap - amount);
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();

        assertEq(stbcToken.balanceOf(alice), initialBalance + amount);
        assertEq(usd0PP100.balanceOf(alice), 0);
        assertEq(usd0PP100.getRemainingUnwrapAllowance(alice), cap - amount);
    }

    function testUnwrapWithCapFailsIfCapNotSet() public {
        uint256 amount = 100e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.prank(admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(UnwrapCapNotSet.selector));
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();
    }

    function testUnwrapWithCapFailsIfExceedsCap() public {
        uint256 amount = 100e18;
        uint256 cap = 50e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountTooBigForCap.selector));
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();
    }

    function testUnwrapWithCapFailsIfNotAuthorized() public {
        uint256 amount = 100e18;
        uint256 cap = 1000e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();
    }

    function testUnwrapWithCapFailsIfZeroAmount() public {
        uint256 amount = 100e18;
        uint256 cap = 1000e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP100.unwrapWithCap(0);
        vm.stopPrank();
    }

    function testUnwrapWithCapFailsWhenPaused() public {
        uint256 amount = 100e18;
        uint256 cap = 1000e18;
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, admin);
        usd0PP100.setUnwrapCap(alice, cap);
        usd0PP100.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();
    }

    function testFuzzSetUnwrapCap(address user, uint256 cap) public {
        vm.assume(user != address(0));

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit UnwrapCapSet(user, cap);
        usd0PP.setUnwrapCap(user, cap);

        assertEq(usd0PP.getUnwrapCap(user), cap);
        vm.stopPrank();
    }

    function testFuzzUnwrapWithCap(uint256 amount, uint256 cap) public {
        // Ensure reasonable bounds and amount <= cap
        amount = bound(amount, 1, type(uint128).max);
        cap = bound(cap, amount, type(uint128).max);

        // Setup bond and mint tokens
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, amount);

        // Setup roles and cap
        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        uint256 initialBalance = stbcToken.balanceOf(alice);

        // Perform unwrap
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CappedUnwrap(alice, amount, cap - amount);
        usd0PP100.unwrapWithCap(amount);
        vm.stopPrank();

        // Verify balances and remaining allowance
        assertEq(stbcToken.balanceOf(alice), initialBalance + amount);
        assertEq(usd0PP100.balanceOf(alice), 0);
        assertEq(usd0PP100.getRemainingUnwrapAllowance(alice), cap - amount);
    }

    function testFuzzMultipleUnwrapsWithinCap(uint256[] calldata amounts, uint256 cap) public {
        // Ensure array is not empty
        vm.assume(amounts.length > 0);

        // Limit array size using bound instead of assume
        uint256 len = bound(amounts.length, 1, 5);

        // Create memory array for bounded amounts
        uint256[] memory boundedAmounts = new uint256[](len);
        uint256 totalAmount;

        // Use smaller bounds for individual amounts
        for (uint256 i = 0; i < len; i++) {
            // Reduced max bound to prevent overflow
            boundedAmounts[i] = bound(amounts[i % amounts.length], 1e6, 1e18); // Use modulo to handle any array length
            totalAmount += boundedAmounts[i];
        }

        // Ensure cap is reasonable but larger than total amount
        cap = bound(cap, totalAmount, totalAmount * 2);

        // Rest of the test remains the same
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, totalAmount);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        uint256 totalUnwrapped;
        vm.startPrank(alice);
        for (uint256 i = 0; i < len; i++) {
            usd0PP100.unwrapWithCap(boundedAmounts[i]);
            totalUnwrapped += boundedAmounts[i];
            assertEq(usd0PP100.getRemainingUnwrapAllowance(alice), cap - totalUnwrapped);
        }
        vm.stopPrank();
    }

    function testFuzzRemainingUnwrapAllowance(uint256 cap, uint256[] calldata unwraps) public {
        // Ensure array is not empty
        vm.assume(unwraps.length > 0);

        // Limit array size using bound instead of assume
        uint256 len = bound(unwraps.length, 1, 3);

        // Create memory array for bounded unwraps
        uint256[] memory boundedUnwraps = new uint256[](len);
        uint256 totalUnwraps;

        // Use smaller bounds for individual unwraps
        for (uint256 i = 0; i < len; i++) {
            // Reduced max bound to prevent overflow
            boundedUnwraps[i] = bound(unwraps[i % unwraps.length], 1e6, 1e18); // Use modulo to handle any array length
            totalUnwraps += boundedUnwraps[i];
        }

        // Ensure cap is reasonable but larger than total unwraps
        cap = bound(cap, totalUnwraps, totalUnwraps * 2);

        // Rest of the test remains the same
        Usd0PP usd0PP100 = scaffoldUsd0ppMintUser(alice, totalUnwraps);

        vm.startPrank(admin);
        registryAccess.grantRole(UNWRAP_CAP_ALLOCATOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_CAPPED_UNWRAP_ROLE, alice);
        usd0PP100.setUnwrapCap(alice, cap);
        vm.stopPrank();

        uint256 expectedRemaining = cap;
        vm.startPrank(alice);
        for (uint256 i = 0; i < len; i++) {
            usd0PP100.unwrapWithCap(boundedUnwraps[i]);
            expectedRemaining -= boundedUnwraps[i];
            assertEq(usd0PP100.getRemainingUnwrapAllowance(alice), expectedRemaining);
        }
        vm.stopPrank();
    }

    function testUnlockUSD0ppWithUsualForSevenDays(uint256 totalMintAmount) public {
        totalMintAmount = bound(totalMintAmount, 1e16, type(uint128).max);
        uint256 dailyMintAmount = totalMintAmount / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;
        uint256 floorPrice = 9e17; // 0.9

        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");

        // Initial data and balances
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), totalMintAmount);

        // Daily minting
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), totalMintAmount);
        uint256 stbcTokenAmount = totalMintAmount;
        totalMintAmount = 0;
        for (uint256 i = 0; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS; i++) {
            usd0PP.mint(dailyMintAmount);
            totalMintAmount += dailyMintAmount;
            assertEq(usd0PP.balanceOf(address(alice)), dailyMintAmount * (i + 1));
            skip(1 days);
        }
        assertEq(usd0PP.balanceOf(address(alice)), totalMintAmount);
        vm.stopPrank();

        // Floor price unlock
        vm.prank(floorPriceUpdater);
        usd0PP.updateFloorPrice(floorPrice);

        uint256 unlockAmount = totalMintAmount / 2;
        vm.prank(alice);
        usd0PP.unlockUsd0ppFloorPrice(unlockAmount);

        // USUAL burn
        uint256 remainingUsd0pp = totalMintAmount - unlockAmount;
        uint256 requiredUsual = usd0PP.calculateRequiredUsual(remainingUsd0pp);

        assertEq(usualToken.balanceOf(address(alice)), 0);
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), requiredUsual * 2);

        // Final unlocking
        vm.startPrank(alice);
        usualToken.approve(address(usd0PP), requiredUsual);
        usd0PP.unlockUSD0ppWithUsual(remainingUsd0pp, requiredUsual);
        vm.stopPrank();

        // Assertions
        assertEq(usd0PP.balanceOf(address(alice)), 0);
        assertEq(usualToken.balanceOf(address(alice)), requiredUsual);
        assertEq(
            stbcToken.balanceOf(address(alice)),
            (unlockAmount * floorPrice / 1e18) + (stbcTokenAmount - unlockAmount)
        );
        // Treasury yield allocation should be equal or greater than the floor rounded value
        assertGe(
            usualToken.balanceOf(address(treasuryYield)),
            requiredUsual * usd0PP.getTreasuryAllocationRate() / BASIS_POINT_BASE
        );
    }

    function testUnlockUSD0ppWithUsualWithPermit(uint256 totalMintAmount) public {
        totalMintAmount = bound(totalMintAmount, 1e16, type(uint128).max);
        uint256 dailyMintAmount = totalMintAmount / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;

        // Setup and initial minting
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), totalMintAmount);

        // Alice mints USD0PP tokens
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), totalMintAmount);
        totalMintAmount = 0;
        for (uint256 i = 0; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS; i++) {
            usd0PP.mint(dailyMintAmount);
            totalMintAmount += dailyMintAmount;
            skip(1 days);
        }
        assertEq(usd0PP.balanceOf(address(alice)), totalMintAmount);
        vm.stopPrank();
        // Mint USUAL tokens and prepare permit data
        uint256 usualRequired = usd0PP.calculateRequiredUsual(dailyMintAmount);
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), usualRequired * 2);

        uint256 deadline = block.timestamp + 2 days;
        PermitApproval memory usualApproval =
            PermitApproval({deadline: deadline, v: 0, r: bytes32(0), s: bytes32(0)});
        PermitApproval memory usd0ppApproval =
            PermitApproval({deadline: deadline, v: 0, r: bytes32(0), s: bytes32(0)});

        // Get permit signatures
        (usualApproval.v, usualApproval.r, usualApproval.s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usd0PP), usualRequired, deadline
        );

        (usd0ppApproval.v, usd0ppApproval.r, usd0ppApproval.s) = _getSelfPermitData(
            address(usd0PP), alice, alicePrivKey, address(usd0PP), dailyMintAmount, deadline
        );

        // Execute unlock with permits
        vm.prank(alice);
        usd0PP.unlockUSD0ppWithUsualWithPermit(
            dailyMintAmount, usualRequired, usualApproval, usd0ppApproval
        );

        // Verify results
        assertEq(usd0PP.balanceOf(alice), totalMintAmount - dailyMintAmount);
        assertEq(usualToken.balanceOf(alice), usualRequired);
    }

    function testUnlockUSD0ppWithUsualWithPermitFailing(uint256 totalMintAmount) public {
        totalMintAmount = bound(totalMintAmount, 1e16, type(uint128).max);
        uint256 dailyMintAmount = totalMintAmount / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;

        // Setup and initial minting
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), totalMintAmount);

        // Alice mints USD0PP tokens
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), totalMintAmount);
        for (uint256 i = 0; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS; i++) {
            usd0PP.mint(dailyMintAmount);
            skip(1 days);
        }
        vm.stopPrank();

        // Mint USUAL tokens and prepare permit data
        uint256 usualRequired = usd0PP.calculateRequiredUsual(dailyMintAmount);
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), usualRequired * 2);

        uint256 deadline = block.timestamp + 2 days;
        PermitApproval memory usualApproval =
            PermitApproval({deadline: deadline, v: 0, r: bytes32(0), s: bytes32(0)});

        PermitApproval memory usd0ppApproval =
            PermitApproval({deadline: deadline, v: 0, r: bytes32(0), s: bytes32(0)});

        (usd0ppApproval.v, usd0ppApproval.r, usd0ppApproval.s) = _getSelfPermitData(
            address(usd0PP), alice, alicePrivKey, address(usd0PP), dailyMintAmount, deadline
        );

        // // ** Scenario 1: Insufficient allowance **
        uint256 insufficientUsual = usualRequired / 2; // Less than required
        (usualApproval.v, usualApproval.r, usualApproval.s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usd0PP), insufficientUsual, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP), 0, usualRequired
            )
        );
        vm.prank(alice);
        usd0PP.unlockUSD0ppWithUsualWithPermit(
            dailyMintAmount, usualRequired, usualApproval, usd0ppApproval
        );

        // ** Scenario 2: Invalid v, r, s (malformed signature) **
        (usualApproval.v, usualApproval.r, usualApproval.s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usd0PP), usualRequired, deadline
        );
        usualApproval.v = usualApproval.v + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP), 0, usualRequired
            )
        );
        vm.prank(alice);
        usd0PP.unlockUSD0ppWithUsualWithPermit(
            dailyMintAmount, usualRequired, usualApproval, usd0ppApproval
        );
        // ** Scenario 3: Invalid token address in permit **
        (usualApproval.v, usualApproval.r, usualApproval.s) = _getSelfPermitData(
            address(usd0PP), alice, alicePrivKey, address(usd0PP), usualRequired, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usd0PP), 0, usualRequired
            )
        );
        vm.prank(alice);
        usd0PP.unlockUSD0ppWithUsualWithPermit(
            dailyMintAmount, usualRequired, usualApproval, usd0ppApproval
        );
    }

    function testCalculateRequiredUsualRoundingFavoringProtocol() public {
        // Use a prime number to ensure division isn't clean
        uint256 testAmount = 1e18 + 31; // Prime number addition

        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), testAmount);

        // Alice mints USD0PP tokens
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), testAmount);
        usd0PP.mint(testAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        registryAccess.grantRole(USD0PP_DURATION_COST_FACTOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_USUAL_DISTRIBUTION_ROLE, admin);
        registryAccess.grantRole(USD0PP_TARGET_REDEMPTION_RATE_ROLE, admin);

        // Set values that will force rounding
        usd0PP.setDurationCostFactor(17); // Prime number
        usd0PP.setUsualDistributionPerUsd0pp(1e18 + 1); // Slightly more than 1
        // Set target redemption rate to ensure adjustmentFactor is 1
        usd0PP.setTargetRedemptionRate(1000); // 10%
        vm.stopPrank();

        // Calculate intermediate steps manually
        uint256 adjustmentFactor = usd0PP.calculateAdjustmentFactor(
            usd0PP.calculateNetOutflows(testAmount),
            usd0PP.calculateWeeklyTargetRedemptions(
                usd0PP.totalSupply(), usd0PP.getTargetRedemptionRate()
            )
        );

        // Calculate without rounding (floor division)
        uint256 floorCalculation = (
            testAmount * usd0PP.getUsualDistributionPerUsd0pp() * usd0PP.getDurationCostFactor()
                * adjustmentFactor
        ) / 1e36;

        // Get the contract's calculation
        uint256 contractCalculation = usd0PP.calculateRequiredUsual(testAmount);

        // Verify that the contract's calculation is greater than floor division
        assertGt(
            contractCalculation,
            floorCalculation,
            "Contract calculation should be greater than floor division"
        );

        // Verify that the difference is at most 1
        assertLe(
            contractCalculation - floorCalculation,
            1,
            "Difference between contract and floor should be at most 1"
        );

        uint256 requiredUsual = usd0PP.calculateRequiredUsual(testAmount);

        assertEq(usualToken.balanceOf(address(alice)), 0);
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), requiredUsual);

        // Final unlocking
        vm.startPrank(alice);
        usualToken.approve(address(usd0PP), requiredUsual);
        usd0PP.unlockUSD0ppWithUsual(testAmount, requiredUsual);
        vm.stopPrank();

        // Treasury yield allocation should be greater than the floor rounded value
        assertGt(
            usualToken.balanceOf(address(treasuryYield)),
            requiredUsual * usd0PP.getTreasuryAllocationRate() / BASIS_POINT_BASE
        );
    }

    function testUnlockUSD0ppWithUsualEdgeCases(
        uint256 durationCostFactor,
        uint256 usualDistributionPerUsd0pp,
        uint256 tvl
    ) public {
        usualDistributionPerUsd0pp = bound(usualDistributionPerUsd0pp, 1, type(uint128).max);
        durationCostFactor = bound(durationCostFactor, 1, type(uint16).max);
        tvl = bound(tvl, 1, type(uint128).max);

        // when all inflow and outflow are the same
        uint256 floorPrice = 1e18;

        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(floorPriceUpdater);
        usd0PP.updateFloorPrice(floorPrice);
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_DURATION_COST_FACTOR_ROLE, admin);
        registryAccess.grantRole(USD0PP_USUAL_DISTRIBUTION_ROLE, admin);
        usd0PP.setDurationCostFactor(durationCostFactor);
        usd0PP.setUsualDistributionPerUsd0pp(usualDistributionPerUsd0pp);
        vm.stopPrank();

        // Initial data and balances
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), tvl);

        // Daily minting
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), tvl);
        usd0PP.mint(tvl);
        usd0PP.unlockUsd0ppFloorPrice(tvl);
        assertEq(usd0PP.totalSupply(), 0);
        assertEq(usd0PP.balanceOf(address(alice)), 0);

        uint256 requiredUsual = usd0PP.calculateRequiredUsual(tvl);
        vm.stopPrank();

        assertGe(
            requiredUsual,
            (tvl * usd0PP.getUsualDistributionPerUsd0pp()) / 1e18 * usd0PP.getDurationCostFactor(),
            "Required USUAL is not in favor of the protocol"
        );

        assertApproxEqAbs(
            requiredUsual,
            (tvl * usd0PP.getUsualDistributionPerUsd0pp()) / 1e18 * usd0PP.getDurationCostFactor(),
            1e18,
            "Required USUAL calculation doesn't match expected value"
        );
    }

    function testUnlockUSD0ppWithUsualWithBadInput(uint256 totalMintAmount) public {
        totalMintAmount = bound(totalMintAmount, 1e16, type(uint128).max);

        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");

        // Initial data and balances
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), totalMintAmount);

        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), totalMintAmount);
        usd0PP.mint(totalMintAmount);
        vm.stopPrank();

        uint256 requiredUsual = usd0PP.calculateRequiredUsual(totalMintAmount);

        // Final unlocking
        vm.startPrank(alice);
        usualToken.approve(address(usd0PP), requiredUsual);
        vm.expectRevert(abi.encodeWithSelector(UsualAmountTooLow.selector));
        usd0PP.unlockUSD0ppWithUsual(totalMintAmount, requiredUsual - 1);
        vm.expectRevert(abi.encodeWithSelector(UsualAmountIsZero.selector));
        usd0PP.unlockUSD0ppWithUsual(0, requiredUsual);
        vm.stopPrank();
    }

    function testUnlockUSD0ppWithUsualWeeklyNetFlowsFuzzy(
        uint256 weeklyInFlows,
        uint256 weeklyOutflows
    ) public {
        weeklyInFlows = bound(weeklyInFlows, 2e18, type(uint128).max);
        weeklyOutflows = bound(weeklyOutflows, 1e18, weeklyInFlows - 1e18);

        uint256 floorPrice = 1e18;

        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(floorPriceUpdater);
        usd0PP.updateFloorPrice(floorPrice);
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), weeklyInFlows);

        uint256 dailyMintAmount = weeklyInFlows / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;
        uint256 dailyOutflows = weeklyOutflows / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;
        vm.startPrank(alice);
        for (uint256 i = 0; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS; i++) {
            skip(1 days);
            stbcToken.approve(address(usd0PP), dailyMintAmount);
            uint256 beforeBalance = usd0PP.balanceOf(address(alice));
            usd0PP.mint(dailyMintAmount);
            uint256 afterBalance = usd0PP.balanceOf(address(alice));
            assertEq(afterBalance, beforeBalance + dailyMintAmount);
            usd0PP.unlockUsd0ppFloorPrice(dailyOutflows);
            assertEq(usd0PP.balanceOf(address(alice)), afterBalance - dailyOutflows);
        }
        vm.stopPrank();

        uint256 remainingUsd0 = stbcToken.balanceOf(address(alice));
        uint256 remainingUsd0pp = usd0PP.balanceOf(address(alice));
        assertApproxEqAbs(
            remainingUsd0pp,
            weeklyInFlows - weeklyOutflows,
            1e18,
            "USD0++ balance doesn't match expected value"
        );

        assertEq(usualToken.balanceOf(address(alice)), 0);
        uint256 requiredUsual = usd0PP.calculateRequiredUsual(remainingUsd0pp);
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), requiredUsual);

        // Final unlocking
        vm.startPrank(alice);
        usualToken.approve(address(usd0PP), requiredUsual);
        assertEq(stbcToken.balanceOf(address(alice)), remainingUsd0);
        usd0PP.unlockUSD0ppWithUsual(remainingUsd0pp, requiredUsual);
        vm.stopPrank();

        assertEq(usualToken.balanceOf(address(alice)), 0);
        assertEq(stbcToken.balanceOf(address(alice)), remainingUsd0 + remainingUsd0pp);
    }

    function testUnlockUSD0ppWithUsualForMultipleScenarios() public {
        RedemptionScenario[] memory scenarios = new RedemptionScenario[](10);

        // Scenario 1: Weekly Outflows greater than Inflows
        scenarios[0] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 400, // 4%
            usualDistributionPerUsd0pp: 0.0009 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 4927.5 * 1e18
        });

        // Scenario 2: Weekly Outflows less than Inflows
        scenarios[1] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 9_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 400, // 4%
            usualDistributionPerUsd0pp: 0.0009 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 821 * 1e18
        });

        // Scenario 3: Case with high redemption rate
        scenarios[2] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 1000, // 10%
            usualDistributionPerUsd0pp: 0.0009 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 1971 * 1e18
        });

        // Scenario 4: Case with non-round numbers
        scenarios[3] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 1000, // 10%
            usualDistributionPerUsd0pp: 1.237 * 1e18, // ~1.237 USUAL per USD0++
            durationCostFactor: 1460,
            expectedUsual: 2_709_030 * 1e18
        });

        // Scenario 5: Case with non-round numbers
        scenarios[4] = RedemptionScenario({
            userRedemption: 9_542_352_234_564_420_000_000_000,
            weeklyOutflows: 464_324_124_124_542_000_000_000_000_000,
            weeklyInflows: 432_132_414_343_543_000_000_000_000_000,
            tvl: 9_887_678_686_889_500_000_000_000_000_000,
            targetRedemptionRate: 37, // 0.37%
            usualDistributionPerUsd0pp: 177_123_456_776_546_000, // ~0.177
            durationCostFactor: 123,
            expectedUsual: 182_984_087_519_512_000_000_000_000
        });

        // Scenario 6: Weekly Outflows greater than Inflows - 2
        scenarios[5] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 240, // 2.4%
            usualDistributionPerUsd0pp: 0.00092374811 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 8429.2015 * 1e18
        });

        // Scenario 7: Weekly Outflows less than Inflows - 2
        scenarios[6] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 9_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 240, // 2.4%
            usualDistributionPerUsd0pp: 0.00092374811 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 1405 * 1e18
        });

        // Scenario 8: Case with high redemption rate - 2
        scenarios[7] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 1000, // 10%
            usualDistributionPerUsd0pp: 0.00092374811 * 1e18, // 0.0009
            durationCostFactor: 1460,
            expectedUsual: 2023 * 1e18
        });

        // Scenario 9: Weekly Outflows greater than Inflows - 3
        scenarios[8] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 10_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 30, // 0.3%
            usualDistributionPerUsd0pp: 0.0009 * 1e18, // 0.0009
            durationCostFactor: 180,
            expectedUsual: 8100 * 1e18
        });

        // Scenario 10: Weekly Outflows less than Inflows - 3
        scenarios[9] = RedemptionScenario({
            userRedemption: 100_000 * 1e18,
            weeklyOutflows: 9_000_000 * 1e18,
            weeklyInflows: 9_500_000 * 1e18,
            tvl: 400_000_000 * 1e18,
            targetRedemptionRate: 30, // 0.3%
            usualDistributionPerUsd0pp: 0.0009 * 1e18, // 0.0009
            durationCostFactor: 180,
            expectedUsual: 1350 * 1e18
        });

        for (uint256 i = 0; i < scenarios.length; i++) {
            _testUnlockUSD0ppWithUsualForScenario(scenarios[i]);
        }
    }

    function _testUnlockUSD0ppWithUsualForScenario(RedemptionScenario memory scenario) public {
        // Setup
        _createRwa();
        Usd0PP usd0PP = _createBond("Test Bond", "USD0PP");
        vm.prank(floorPriceUpdater);
        usd0PP.updateFloorPrice(1e18);

        // Set up configuration
        vm.startPrank(admin);
        registryAccess.grantRole(USD0PP_TARGET_REDEMPTION_RATE_ROLE, admin);
        registryAccess.grantRole(USD0PP_USUAL_DISTRIBUTION_ROLE, admin);
        registryAccess.grantRole(USD0PP_DURATION_COST_FACTOR_ROLE, admin);

        usd0PP.setTargetRedemptionRate(scenario.targetRedemptionRate);
        usd0PP.setUsualDistributionPerUsd0pp(scenario.usualDistributionPerUsd0pp);
        usd0PP.setDurationCostFactor(scenario.durationCostFactor);
        vm.stopPrank();

        // Initial data and balances
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), scenario.tvl * 2);

        // Setup initial TVL
        vm.startPrank(alice);
        uint256 actualTotalMint = scenario.tvl;
        if (scenario.weeklyOutflows > scenario.weeklyInflows) {
            actualTotalMint += scenario.weeklyOutflows - scenario.weeklyInflows;
        } else {
            actualTotalMint -= scenario.weeklyInflows - scenario.weeklyOutflows;
        }
        stbcToken.approve(address(usd0PP), actualTotalMint);
        usd0PP.mint(actualTotalMint);
        vm.stopPrank();

        skip(10 days);

        // Mock daily flows
        uint256 dailyOutflows = scenario.weeklyOutflows / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;
        uint256 dailyInflows = scenario.weeklyInflows / USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS;

        // Simulate daily activities
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), scenario.tvl);
        for (uint256 i = 0; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS - 1; i++) {
            skip(1 days);
            usd0PP.mint(dailyInflows);
            usd0PP.unlockUsd0ppFloorPrice(dailyOutflows);
        }
        skip(1 days);
        usd0PP.mint(
            scenario.weeklyInflows - dailyInflows * (USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS - 1)
        );
        usd0PP.unlockUsd0ppFloorPrice(
            scenario.weeklyOutflows - dailyOutflows * (USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS - 1)
        );
        vm.stopPrank();

        // Calculate and verify net outflows
        uint256 netOutflows = usd0PP.calculateNetOutflows(scenario.userRedemption);
        uint256 expectedNetOutflows;
        if (scenario.weeklyOutflows > scenario.weeklyInflows) {
            expectedNetOutflows =
                scenario.userRedemption + (scenario.weeklyOutflows - scenario.weeklyInflows);
        } else {
            expectedNetOutflows = scenario.userRedemption;
        }
        assertApproxEqAbs(netOutflows, expectedNetOutflows, 3, "Net outflows calculation mismatch");

        // Calculate and verify weekly target redemptions
        uint256 weeklyTarget =
            usd0PP.calculateWeeklyTargetRedemptions(scenario.tvl, scenario.targetRedemptionRate);
        uint256 expectedWeeklyTarget =
            (scenario.tvl * scenario.targetRedemptionRate) / BASIS_POINT_BASE;
        assertApproxEqAbs(
            weeklyTarget, expectedWeeklyTarget, 3, "Weekly target redemptions mismatch"
        );

        // Calculate and verify adjustment factor
        uint256 adjustmentFactor = usd0PP.calculateAdjustmentFactor(netOutflows, weeklyTarget);
        uint256 expectedAdjustmentFactor = Math.min((netOutflows * 1e18) / weeklyTarget, 1e18);
        assertApproxEqAbs(
            adjustmentFactor, expectedAdjustmentFactor, 3, "Adjustment factor mismatch"
        );

        // Calculate and verify required USUAL
        uint256 requiredUsual = usd0PP.calculateRequiredUsual(scenario.userRedemption);
        assertApproxEqAbs(
            requiredUsual, scenario.expectedUsual, 1e18, "Required USUAL calculation mismatch"
        );

        // Verify actual redemption works
        vm.prank(address(airdropDistribution));
        usualToken.mint(address(alice), requiredUsual);

        vm.startPrank(alice);
        usualToken.approve(address(usd0PP), requiredUsual);
        uint256 stbcBalanceBefore = stbcToken.balanceOf(address(alice));
        usd0PP.unlockUSD0ppWithUsual(scenario.userRedemption, requiredUsual);
        uint256 stbcBalanceAfter = stbcToken.balanceOf(address(alice));
        vm.stopPrank();

        // Verify redemption results
        assertEq(
            stbcBalanceAfter - stbcBalanceBefore,
            scenario.userRedemption,
            "Incorrect STBC received from redemption"
        );
        assertEq(usualToken.balanceOf(address(alice)), 0, "USUAL tokens not fully consumed");
    }

    // Test setting the target redemption rate
    function testSetTargetRedemptionRate(uint256 newValue) public {
        newValue = bound(newValue, 1, BASIS_POINT_BASE);
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_TARGET_REDEMPTION_RATE_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit TargetRedemptionRateSet(newValue);

        usd0PP.setTargetRedemptionRate(newValue);
        vm.stopPrank();
    }

    function testSetTargetRedemptionRateFailsIfNotAuthorized(uint256 newValue) public {
        newValue = bound(newValue, 1, BASIS_POINT_BASE);
        vm.startPrank(address(admin));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.setTargetRedemptionRate(newValue);
        vm.stopPrank();
    }

    function testSetTargetRedemptionRateFailsIfBadInput() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_TARGET_REDEMPTION_RATE_ROLE, admin);

        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        usd0PP.setTargetRedemptionRate(0);

        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        usd0PP.setTargetRedemptionRate(BASIS_POINT_BASE + 1);

        vm.stopPrank();
    }

    // Test setting the usual distribution per USD0++
    function testSetUsualDistributionPerUsd0pp(uint256 newValue) public {
        newValue = bound(newValue, 1, type(uint256).max);
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_USUAL_DISTRIBUTION_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit UsualDistributionPerUsd0ppSet(newValue);

        usd0PP.setUsualDistributionPerUsd0pp(newValue);
        vm.stopPrank();
    }

    function testSetUsualDistributionPerUsd0ppFailsIfNotAuthorized(uint256 newValue) public {
        newValue = bound(newValue, 1, type(uint256).max);
        vm.startPrank(address(admin));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.setUsualDistributionPerUsd0pp(newValue);
        vm.stopPrank();
    }

    function testSetUsualDistributionPerUsd0ppFailsIfBadInput() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_USUAL_DISTRIBUTION_ROLE, admin);

        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP.setUsualDistributionPerUsd0pp(0);

        vm.stopPrank();
    }

    // Test setting the duration cost factor
    function testSetDurationCostFactor(uint256 newValue) public {
        newValue = bound(newValue, 1, type(uint256).max);
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_DURATION_COST_FACTOR_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit DurationCostFactorSet(newValue);

        usd0PP.setDurationCostFactor(newValue);
        vm.stopPrank();
    }

    function testSetDurationCostFactorFailsIfNotAuthorized(uint256 newValue) public {
        newValue = bound(newValue, 1, type(uint256).max);
        vm.startPrank(address(admin));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.setDurationCostFactor(newValue);
        vm.stopPrank();
    }

    function testSetDurationCostFactorFailsIfBadInput() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_DURATION_COST_FACTOR_ROLE, admin);

        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usd0PP.setDurationCostFactor(0);

        vm.stopPrank();
    }

    // Test setting the treasury allocation rate
    function testSetTreasuryAllocationRate(uint256 newValue) public {
        newValue = bound(newValue, 1, BASIS_POINT_BASE);
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_TREASURY_ALLOCATION_RATE_ROLE, admin);

        vm.expectEmit(true, true, true, true);
        emit TreasuryAllocationRateSet(newValue);

        usd0PP.setTreasuryAllocationRate(newValue);
        vm.stopPrank();
    }

    function testSetTreasuryAllocationRateFailsIfNotAuthorized(uint256 newValue) public {
        newValue = bound(newValue, 1, BASIS_POINT_BASE);
        vm.startPrank(address(admin));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.setTreasuryAllocationRate(newValue);
        vm.stopPrank();
    }

    function testSetTreasuryAllocationRateFailsIfBadInput() public {
        vm.startPrank(address(admin));
        registryAccess.grantRole(USD0PP_TREASURY_ALLOCATION_RATE_ROLE, admin);

        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        usd0PP.setTreasuryAllocationRate(0);

        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        usd0PP.setTreasuryAllocationRate(BASIS_POINT_BASE + 1);

        vm.stopPrank();
    }
}
