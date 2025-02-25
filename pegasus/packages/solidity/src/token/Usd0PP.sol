// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {IUsd0} from "./../interfaces/token/IUsd0.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IAirdropDistribution} from "src/interfaces/airdrop/IAirdropDistribution.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {Approval as PermitApproval} from "src/interfaces/IDaoCollateral.sol";

import {
    CONTRACT_YIELD_TREASURY,
    DEFAULT_ADMIN_ROLE,
    PEG_MAINTAINER_ROLE,
    EARLY_BOND_UNLOCK_ROLE,
    FLOOR_PRICE_UPDATER_ROLE,
    BOND_DURATION_FOUR_YEAR,
    END_OF_EARLY_UNLOCK_PERIOD,
    CURVE_POOL_USD0_USD0PP,
    CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0,
    CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP,
    PAUSING_CONTRACTS_ROLE,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    PEG_MAINTAINER_UNLIMITED_ROLE,
    UNWRAP_CAP_ALLOCATOR_ROLE,
    USD0PP_CAPPED_UNWRAP_ROLE,
    BASIS_POINT_BASE,
    USD0PP_USUAL_DISTRIBUTION_ROLE,
    USD0PP_DURATION_COST_FACTOR_ROLE,
    USD0PP_TREASURY_ALLOCATION_RATE_ROLE,
    USD0PP_TARGET_REDEMPTION_RATE_ROLE,
    CONTRACT_USUAL,
    INITIAL_USUAL_BURN_TREASURY_ALLOCATION_RATE,
    INITIAL_USUAL_BURN_DURATION_COST_FACTOR,
    INITIAL_USUAL_BURN_USUAL_DISTRIBUTION_PER_USD0PP,
    INITIAL_USUAL_BURN_TARGET_REDEMPTION_RATE,
    USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS,
    SCALAR_ONE
} from "src/constants.sol";

import {
    BondNotStarted,
    BondFinished,
    BondNotFinished,
    OutsideEarlyUnlockTimeframe,
    NotAuthorized,
    AmountIsZero,
    NullAddress,
    Blacklisted,
    AmountTooBig,
    PARNotRequired,
    PARNotSuccessful,
    ApprovalFailed,
    PARUSD0InputExceedsBalance,
    NotPermittedToEarlyUnlock,
    InvalidInput,
    InvalidInputArraysLength,
    FloorPriceTooHigh,
    AmountMustBeGreaterThanZero,
    InsufficientUsd0ppBalance,
    FloorPriceNotSet,
    OutOfBounds,
    UnwrapCapNotSet,
    AmountTooBigForCap,
    UsualAmountTooLow,
    UsualAmountIsZero
} from "src/errors.sol";

/// @title   Usd0PP Contract
/// @notice  Manages bond-like financial instruments for the UsualDAO ecosystem, providing functionality for minting, transferring, and unwrapping bonds.
/// @dev     Inherits from ERC20, ERC20PermitUpgradeable, and ReentrancyGuardUpgradeable to provide a range of functionalities along with protections against reentrancy attacks.
/// @dev     This contract is upgradeable, allowing for future improvements and enhancements.
/// @author  Usual Tech team

contract Usd0PP is
    IUsd0PP,
    ERC20PausableUpgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CheckAccessControl for IRegistryAccess;
    using SafeERC20 for IERC20;
    using SafeERC20 for IUsual;

    /// @custom:storage-location erc7201:Usd0PP.storage.v0
    struct Usd0PPStorageV0 {
        /// The start time of the bond period.
        uint256 bondStart;
        /// The address of the registry contract.
        IRegistryContract registryContract;
        /// The address of the registry access contract.
        IRegistryAccess registryAccess;
        /// The USD0 token.
        IERC20 usd0;
        uint256 bondEarlyUnlockStart;
        uint256 bondEarlyUnlockEnd;
        mapping(address => uint256) bondEarlyUnlockAllowedAmount;
        mapping(address => bool) bondEarlyUnlockDisabled;
        /// The current floor price for unlocking USD0++ to USD0 (18 decimal places)
        uint256 floorPrice;
        /// The USUAL token
        IUsual usual;
        /// Tracks daily USD0++ inflows
        mapping(uint256 => uint256) dailyUsd0ppInflows;
        /// Tracks daily USD0++ outflows
        mapping(uint256 => uint256) dailyUsd0ppOutflows;
        /// USUAL distributed per USD0++ per day (18 decimal places)
        uint256 usualDistributionPerUsd0pp;
        /// The percentage of burned USUAL that goes to the treasury (basis points)
        uint256 treasuryAllocationRate;
        /// Daily redemption target rate (basis points of total supply)
        uint256 targetRedemptionRate;
        /// Duration cost adjustment factor in days
        uint256 durationCostFactor;
        /// Mapping of addresses to their unwrap cap
        mapping(address => uint256) unwrapCaps;
    }

    // keccak256(abi.encode(uint256(keccak256("Usd0PP.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant Usd0PPStorageV0Location =
        0x1519c21cc5b6e62f5c0018a7d32a0d00805e5b91f6eaa9f7bc303641242e3000;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usd0ppStorageV0() internal pure returns (Usd0PPStorageV0 storage $) {
        bytes32 position = Usd0PPStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a bond is unwrapped.
    /// @param user The address of the user unwrapping the bond.
    /// @param amount The amount of the bond unwrapped.
    event BondUnwrapped(address indexed user, uint256 amount);

    /// @notice Emitted when a bond is unwrapped during the temporary unlock period.
    /// @param user The address of the user unwrapping the bond.
    /// @param amount The amount of the bond unwrapped.
    event BondUnwrappedDuringEarlyUnlock(address indexed user, uint256 amount);

    /// @notice Event emitted when a bond is early redeemed by burning USUAL
    /// @param user The address of the user early redeeming the bond
    /// @param usd0ppAmount The amount of USD0++ early redeemed
    /// @param usualBurned The amount of USUAL burned
    /// @param usualToTreasury The amount of USUAL sent to the treasury
    event BondUnwrappedEarlyWithUsualBurn(
        address indexed user, uint256 usd0ppAmount, uint256 usualBurned, uint256 usualToTreasury
    );

    /// @notice Emitted when the PAR mechanism is triggered
    /// @param user The address of the caller triggering the mechanism
    /// @param amount The amount of USD0 supplied to the Curvepool to return to PAR.
    event PARMechanismActivated(address indexed user, uint256 amount);

    /// @notice Emitted when an emergency withdrawal occurs.
    /// @param account The address of the account initiating the emergency withdrawal.
    /// @param balance The balance withdrawn.
    event EmergencyWithdraw(address indexed account, uint256 balance);

    /// @notice Emitted when an address temporary redemption is disabled.
    /// @param user The address of the user being disabled for temporary redemptions.
    event BondEarlyUnlockDisabled(address indexed user);

    /// @notice Event emitted when the floor price is updated
    /// @param newFloorPrice The new floor price value
    event FloorPriceUpdated(uint256 newFloorPrice);

    /// @notice Event emitted when USD0++ is unlocked to USD0
    /// @param user The address of the user unlocking USD0++
    /// @param usd0ppAmount The amount of USD0++ unlocked
    /// @param usd0Amount The amount of USD0 received
    event Usd0ppUnlockedFloorPrice(address indexed user, uint256 usd0ppAmount, uint256 usd0Amount);

    /// @notice Event emitted when the early unlock balances are set.
    /// @param addressesToAllocateTo The addresses to allocate the balances to.
    /// @param earlyUnlockBalances The early unlock balances to allocate.
    event EarlyUnlockBalancesSet(address[] addressesToAllocateTo, uint256[] earlyUnlockBalances);

    /// @notice Event emitted when the early unlock period is set.
    /// @param earlyUnlockStart The start of the early unlock period.
    /// @param earlyUnlockEnd The end of the early unlock period.
    event EarlyUnlockPeriodSet(uint256 earlyUnlockStart, uint256 earlyUnlockEnd);

    /// @notice Emitted when an unwrap cap is set for an address
    event UnwrapCapSet(address indexed user, uint256 cap);

    /// @notice Emitted when USD0++ is unwrapped by a USD0PP_CAPPED_UNWRAP_ROLE address
    event CappedUnwrap(address indexed user, uint256 amount, uint256 remainingAllowance);

    /// @notice Event emitted when the daily USD0++ inflow is updated
    /// @param dayIndex Index of the day (unix timestamp / seconds per day)
    /// @param amount The amount of USD0++ inflow
    event DailyUsd0ppInflowUpdated(uint256 dayIndex, uint256 amount);

    /// @notice Event emitted when the daily USD0++ outflow is updated
    /// @param dayIndex Index of the day (unix timestamp / seconds per day)
    /// @param amount The amount of USD0++ outflow
    event DailyUsd0ppOutflowUpdated(uint256 dayIndex, uint256 amount);

    /// @notice Event emitted when the USUAL distribution rate is set
    /// @param newRate The new USUAL distribution rate
    event UsualDistributionPerUsd0ppSet(uint256 newRate);

    /// @notice Event emitted when the duration cost factor is set
    /// @param newFactor The new duration cost factor
    event DurationCostFactorSet(uint256 newFactor);

    /// @notice Event emitted when the target redemption rate is set
    /// @param newRate The new target redemption rate
    event TargetRedemptionRateSet(uint256 newRate);

    /// @notice Event emitted when the treasury allocation is set
    /// @param newRate The new treasury allocation rate
    event TreasuryAllocationRateSet(uint256 newRate);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with required parameters for early unlock with usual burn.
    function initializeV2() public reinitializer(3) {
        if (
            INITIAL_USUAL_BURN_TREASURY_ALLOCATION_RATE == 0
                || INITIAL_USUAL_BURN_TREASURY_ALLOCATION_RATE > BASIS_POINT_BASE
        ) {
            revert InvalidInput();
        }

        if (INITIAL_USUAL_BURN_DURATION_COST_FACTOR == 0) {
            revert InvalidInput();
        }

        if (INITIAL_USUAL_BURN_USUAL_DISTRIBUTION_PER_USD0PP == 0) {
            revert InvalidInput();
        }

        if (
            INITIAL_USUAL_BURN_TARGET_REDEMPTION_RATE == 0
                || INITIAL_USUAL_BURN_TARGET_REDEMPTION_RATE > BASIS_POINT_BASE
        ) {
            revert InvalidInput();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.treasuryAllocationRate = INITIAL_USUAL_BURN_TREASURY_ALLOCATION_RATE;
        $.durationCostFactor = INITIAL_USUAL_BURN_DURATION_COST_FACTOR;
        $.usualDistributionPerUsd0pp = INITIAL_USUAL_BURN_USUAL_DISTRIBUTION_PER_USD0PP;
        $.targetRedemptionRate = INITIAL_USUAL_BURN_TARGET_REDEMPTION_RATE;
        $.usual = IUsual($.registryContract.getContract(CONTRACT_USUAL));

        emit TreasuryAllocationRateSet($.treasuryAllocationRate);
        emit DurationCostFactorSet($.durationCostFactor);
        emit UsualDistributionPerUsd0ppSet($.usualDistributionPerUsd0pp);
        emit TargetRedemptionRateSet($.targetRedemptionRate);
    }

    // @inheritdoc IUsd0PP
    function setupEarlyUnlockPeriod(uint256 bondEarlyUnlockStart, uint256 bondEarlyUnlockEnd)
        public
    {
        if (bondEarlyUnlockEnd > END_OF_EARLY_UNLOCK_PERIOD) {
            revert OutOfBounds();
        }
        if (bondEarlyUnlockStart >= bondEarlyUnlockEnd) {
            revert InvalidInput();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(EARLY_BOND_UNLOCK_ROLE);
        $.bondEarlyUnlockStart = bondEarlyUnlockStart;
        $.bondEarlyUnlockEnd = bondEarlyUnlockEnd;

        emit EarlyUnlockPeriodSet(bondEarlyUnlockStart, bondEarlyUnlockEnd);
    }

    /*//////////////////////////////////////////////////////////////
                             External Functions
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IUsd0PP
    function pause() public {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    // @inheritdoc IUsd0PP
    function unpause() external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    // @inheritdoc IUsd0PP
    function mint(uint256 amountUsd0) public nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if the bond period isn't started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        // revert if the bond period is finished
        if (block.timestamp >= $.bondStart + BOND_DURATION_FOUR_YEAR) {
            revert BondFinished();
        }

        // get the collateral token for the bond
        $.usd0.safeTransferFrom(msg.sender, address(this), amountUsd0);

        // update the daily USD0++ inflows
        _updateDailyUSD0pplFlow(amountUsd0, true);

        // mint the bond for the sender
        _mint(msg.sender, amountUsd0);
    }

    // @inheritdoc IUsd0PP
    function mintWithPermit(uint256 amountUsd0, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        try IERC20Permit(address($.usd0)).permit(
            msg.sender, address(this), amountUsd0, deadline, v, r, s
        ) {} catch {} // solhint-disable-line no-empty-blocks

        mint(amountUsd0);
    }

    // @inheritdoc IUsd0PP
    function unwrap() external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if the bond period is not finished
        if (block.timestamp < $.bondStart + BOND_DURATION_FOUR_YEAR) {
            revert BondNotFinished();
        }
        uint256 usd0PPBalance = balanceOf(msg.sender);

        _burnAndUpdateFlow(msg.sender, usd0PPBalance);

        $.usd0.safeTransfer(msg.sender, usd0PPBalance);

        emit BondUnwrapped(msg.sender, usd0PPBalance);
    }

    // @inheritdoc IUsd0PP
    function temporaryOneToOneExitUnwrap(uint256 amountToUnwrap)
        external
        nonReentrant
        whenNotPaused
    {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if not during the temporary exit period
        if (block.timestamp < $.bondEarlyUnlockStart || block.timestamp > $.bondEarlyUnlockEnd) {
            revert OutsideEarlyUnlockTimeframe();
        }

        if ($.bondEarlyUnlockDisabled[msg.sender]) {
            revert NotAuthorized();
        }

        if (amountToUnwrap > $.bondEarlyUnlockAllowedAmount[msg.sender]) {
            revert NotPermittedToEarlyUnlock();
        }

        if (balanceOf(msg.sender) < amountToUnwrap) {
            revert AmountTooBig();
        }

        // this is a one-time option. It consumes the entire balance, even if only used partially.
        $.bondEarlyUnlockAllowedAmount[msg.sender] = 0;

        IAirdropDistribution airdropContract =
            IAirdropDistribution($.registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION));

        airdropContract.voidAnyOutstandingAirdrop(msg.sender);

        _burnAndUpdateFlow(msg.sender, amountToUnwrap);

        $.usd0.safeTransfer(msg.sender, amountToUnwrap);

        emit BondUnwrappedDuringEarlyUnlock(msg.sender, amountToUnwrap);
    }

    // @inheritdoc IUsd0PP
    function allocateEarlyUnlockBalance(
        address[] calldata addressesToAllocateTo,
        uint256[] calldata balancesToAllocate
    ) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(EARLY_BOND_UNLOCK_ROLE);

        if (addressesToAllocateTo.length != balancesToAllocate.length) {
            revert InvalidInputArraysLength();
        }

        for (uint256 i; i < addressesToAllocateTo.length;) {
            if (addressesToAllocateTo[i] == address(0)) {
                revert NullAddress();
            }
            $.bondEarlyUnlockAllowedAmount[addressesToAllocateTo[i]] = balancesToAllocate[i];

            unchecked {
                ++i;
            }
        }

        emit EarlyUnlockBalancesSet(addressesToAllocateTo, balancesToAllocate);
    }

    // @inheritdoc IUsd0PP
    function setUnwrapCap(address user, uint256 cap) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(UNWRAP_CAP_ALLOCATOR_ROLE);

        $.unwrapCaps[user] = cap;
        emit UnwrapCapSet(user, cap);
    }

    // @inheritdoc IUsd0PP
    function unwrapWithCap(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert AmountIsZero();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(USD0PP_CAPPED_UNWRAP_ROLE);

        // Check cap is set
        if ($.unwrapCaps[msg.sender] == 0) {
            revert UnwrapCapNotSet();
        }

        if (amount > $.unwrapCaps[msg.sender]) {
            revert AmountTooBigForCap();
        }

        $.unwrapCaps[msg.sender] -= amount;

        // Not considered as an outflow as per specification
        _burn(msg.sender, amount);
        $.usd0.safeTransfer(msg.sender, amount);

        emit CappedUnwrap(msg.sender, amount, $.unwrapCaps[msg.sender]);
    }

    // @inheritdoc IUsd0PP
    function unwrapPegMaintainer(uint256 amount) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(PEG_MAINTAINER_UNLIMITED_ROLE);
        // revert if the bond period has not started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        uint256 usd0PPBalance = balanceOf(msg.sender);
        if (usd0PPBalance < amount) {
            revert AmountTooBig();
        }
        _burnAndUpdateFlow(msg.sender, amount);

        $.usd0.safeTransfer(msg.sender, amount);

        emit BondUnwrapped(msg.sender, amount);
    }

    // @inheritdoc IUsd0PP
    function triggerPARMechanismCurvepool(
        uint256 parUsd0Amount,
        uint256 minimumPARMechanismGainedAmount
    ) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(PEG_MAINTAINER_ROLE);
        // revert if the bond period has not started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        if (parUsd0Amount == 0 || minimumPARMechanismGainedAmount == 0) {
            revert AmountIsZero();
        }
        IERC20 usd0 = $.usd0;

        uint256 usd0BalanceBeforePAR = usd0.balanceOf(address(this));
        uint256 usd0ppBalanceBeforePAR = balanceOf(address(this));
        if (usd0BalanceBeforePAR < parUsd0Amount) {
            revert PARUSD0InputExceedsBalance();
        }

        ICurvePool curvepool = ICurvePool(address(CURVE_POOL_USD0_USD0PP));
        //@notice, deposit USD0 into curvepool to receive USD0++
        if (!(usd0.approve(address(curvepool), parUsd0Amount))) {
            revert ApprovalFailed();
        }

        uint256 receivedUsd0pp = curvepool.exchange(
            CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0,
            CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP,
            parUsd0Amount,
            parUsd0Amount + minimumPARMechanismGainedAmount,
            address(this)
        );
        if (receivedUsd0pp < parUsd0Amount) {
            revert PARNotRequired();
        }

        uint256 usd0ppBalanceChangeAfterPAR = balanceOf(address(this)) - usd0ppBalanceBeforePAR;

        _burnAndUpdateFlow(address(this), usd0ppBalanceChangeAfterPAR);
        emit BondUnwrapped(address(this), usd0ppBalanceChangeAfterPAR);

        uint256 gainedUSD0AmountPAR = usd0ppBalanceChangeAfterPAR - parUsd0Amount;

        usd0.safeTransfer(
            $.registryContract.getContract(CONTRACT_YIELD_TREASURY), gainedUSD0AmountPAR
        );

        if (usd0.balanceOf(address(this)) < totalSupply()) {
            revert PARNotSuccessful();
        }

        emit PARMechanismActivated(msg.sender, gainedUSD0AmountPAR);
    }

    /// @notice function for executing the emergency withdrawal of Usd0.
    /// @param  safeAccount The address of the account to withdraw the Usd0 to.
    /// @dev    Reverts if the caller does not have the DEFAULT_ADMIN_ROLE role.
    function emergencyWithdraw(address safeAccount) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if (!$.registryAccess.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        IERC20 usd0 = $.usd0;

        uint256 balance = usd0.balanceOf(address(this));
        // get the collateral token for the bond
        usd0.safeTransfer(safeAccount, balance);

        // Pause the contract
        if (!paused()) {
            _pause();
        }

        emit EmergencyWithdraw(safeAccount, balance);
    }

    // @inheritdoc IUsd0PP
    function updateFloorPrice(uint256 newFloorPrice) external {
        if (newFloorPrice > 1e18) {
            revert FloorPriceTooHigh();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(FLOOR_PRICE_UPDATER_ROLE);

        $.floorPrice = newFloorPrice;

        emit FloorPriceUpdated(newFloorPrice);
    }

    // @inheritdoc IUsd0PP
    function unlockUsd0ppFloorPrice(uint256 usd0ppAmount) external nonReentrant whenNotPaused {
        if (usd0ppAmount == 0) {
            revert AmountMustBeGreaterThanZero();
        }
        if (balanceOf(msg.sender) < usd0ppAmount) {
            revert InsufficientUsd0ppBalance();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if ($.floorPrice == 0) {
            revert FloorPriceNotSet();
        }

        // as floorPrice can't be greater than 1e18, we will never have a usd0Amount greater than the usd0 backing
        uint256 usd0Amount = Math.mulDiv(usd0ppAmount, $.floorPrice, 1e18, Math.Rounding.Floor);

        _burnAndUpdateFlow(msg.sender, usd0ppAmount);
        $.usd0.safeTransfer(msg.sender, usd0Amount);

        // Calculate and transfer the delta to the treasury
        uint256 delta = usd0ppAmount - usd0Amount;
        if (delta > 0) {
            address treasury = $.registryContract.getContract(CONTRACT_YIELD_TREASURY);
            $.usd0.safeTransfer(treasury, delta);
        }

        emit Usd0ppUnlockedFloorPrice(msg.sender, usd0ppAmount, usd0Amount);
    }

    // @inheritdoc IUsd0PP
    function setBondEarlyUnlockDisabled(address user) external whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if (msg.sender != $.registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR)) {
            revert NotAuthorized();
        }
        $.bondEarlyUnlockDisabled[user] = true;
        emit BondEarlyUnlockDisabled(user);
    }

    // @inheritdoc IUsd0PP
    function unlockUSD0ppWithUsual(uint256 usd0ppAmount, uint256 maxUsualAmount)
        public
        nonReentrant
        whenNotPaused
    {
        uint256 requiredUsual = calculateRequiredUsual(usd0ppAmount);
        if (requiredUsual == 0) {
            revert UsualAmountIsZero();
        }
        if (requiredUsual > maxUsualAmount) {
            revert UsualAmountTooLow();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // Calculate USUAL allocation and transfer in one operation with ceiling rounding
        uint256 usualToTreasury = Math.mulDiv(
            requiredUsual, $.treasuryAllocationRate, BASIS_POINT_BASE, Math.Rounding.Ceil
        );

        $.usual.safeTransferFrom(msg.sender, address(this), requiredUsual);
        $.usual.safeTransfer(
            $.registryContract.getContract(CONTRACT_YIELD_TREASURY), usualToTreasury
        );
        uint256 usualToBurn = requiredUsual - usualToTreasury;
        if (usualToBurn > 0) {
            $.usual.burn(usualToBurn);
        }

        _burnAndUpdateFlow(msg.sender, usd0ppAmount);
        $.usd0.safeTransfer(msg.sender, usd0ppAmount);

        emit BondUnwrappedEarlyWithUsualBurn(msg.sender, usd0ppAmount, usualToBurn, usualToTreasury);
    }

    // @inheritdoc IUsd0PP
    function unlockUSD0ppWithUsualWithPermit(
        uint256 usd0ppAmount,
        uint256 maxUsualAmount,
        PermitApproval calldata usualApproval,
        PermitApproval calldata usd0ppApproval
    ) external whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // Execute the USUAL permit
        try IERC20Permit(address($.usual)).permit(
            msg.sender,
            address(this),
            maxUsualAmount,
            usualApproval.deadline,
            usualApproval.v,
            usualApproval.r,
            usualApproval.s
        ) {} catch {} // solhint-disable-line no-empty-blocks

        // Execute the USD0++ permit
        try IERC20Permit(address(this)).permit(
            msg.sender,
            address(this),
            usd0ppAmount,
            usd0ppApproval.deadline,
            usd0ppApproval.v,
            usd0ppApproval.r,
            usd0ppApproval.s
        ) {} catch {} // solhint-disable-line no-empty-blocks

        // Call the standard unlock function
        unlockUSD0ppWithUsual(usd0ppAmount, maxUsualAmount);
    }

    // @inheritdoc IUsd0PP
    function setUsualDistributionPerUsd0pp(uint256 newRate) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_USUAL_DISTRIBUTION_ROLE);

        if (newRate == 0) {
            revert AmountIsZero();
        }

        $.usualDistributionPerUsd0pp = newRate;
        emit UsualDistributionPerUsd0ppSet(newRate);
    }

    // @inheritdoc IUsd0PP
    function setDurationCostFactor(uint256 newFactor) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_DURATION_COST_FACTOR_ROLE);

        if (newFactor == 0) {
            revert AmountIsZero();
        }

        $.durationCostFactor = newFactor;
        emit DurationCostFactorSet(newFactor);
    }

    // @inheritdoc IUsd0PP
    function setTreasuryAllocationRate(uint256 newRate) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_TREASURY_ALLOCATION_RATE_ROLE);

        if (newRate == 0 || newRate > BASIS_POINT_BASE) {
            revert InvalidInput();
        }

        $.treasuryAllocationRate = newRate;
        emit TreasuryAllocationRateSet(newRate);
    }

    // @inheritdoc IUsd0PP
    function setTargetRedemptionRate(uint256 newRate) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_TARGET_REDEMPTION_RATE_ROLE);

        if (newRate == 0 || newRate > BASIS_POINT_BASE) {
            revert InvalidInput();
        }

        $.targetRedemptionRate = newRate;
        emit TargetRedemptionRateSet(newRate);
    }

    /*//////////////////////////////////////////////////////////////
                             View Functions
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IUsd0PP
    function totalBondTimes() public pure returns (uint256) {
        return BOND_DURATION_FOUR_YEAR;
    }

    // @inheritdoc IUsd0PP
    function getBondEarlyUnlockDisabled(address user) external view returns (bool) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockDisabled[user];
    }

    // @inheritdoc IUsd0PP
    function getStartTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondStart;
    }

    // @inheritdoc IUsd0PP
    function getEndTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondStart + BOND_DURATION_FOUR_YEAR;
    }

    // @inheritdoc IUsd0PP
    function getFloorPrice() external view returns (uint256) {
        return _usd0ppStorageV0().floorPrice;
    }

    // @inheritdoc IUsd0PP
    function getTemporaryUnlockStartTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockStart;
    }

    // @inheritdoc IUsd0PP
    function getTemporaryUnlockEndTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockEnd;
    }

    // @inheritdoc IUsd0PP
    function getAllocationEarlyUnlock(address addressToCheck) external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockAllowedAmount[addressToCheck];
    }

    // @inheritdoc IUsd0PP
    function getUnwrapCap(address user) external view returns (uint256) {
        return _usd0ppStorageV0().unwrapCaps[user];
    }

    // @inheritdoc IUsd0PP
    function getRemainingUnwrapAllowance(address user) external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.unwrapCaps[user];
    }

    // @inheritdoc IUsd0PP
    function getTargetRedemptionRate() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.targetRedemptionRate;
    }

    // @inheritdoc IUsd0PP
    function getUsualDistributionPerUsd0pp() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.usualDistributionPerUsd0pp;
    }

    // @inheritdoc IUsd0PP
    function getTreasuryAllocationRate() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.treasuryAllocationRate;
    }

    // @inheritdoc IUsd0PP
    function getDurationCostFactor() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.durationCostFactor;
    }

    // @inheritdoc IUsd0PP
    function getDailyUsd0ppInflows(uint256 dayIndex) external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.dailyUsd0ppInflows[dayIndex];
    }

    // @inheritdoc IUsd0PP
    function getDailyUsd0ppOutflows(uint256 dayIndex) external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.dailyUsd0ppOutflows[dayIndex];
    }

    // @inheritdoc IUsd0PP
    function calculateWeeklyTargetRedemptions(uint256 tvl, uint256 targetRedemptionRate)
        public
        pure
        returns (uint256)
    {
        return Math.mulDiv(tvl, targetRedemptionRate, BASIS_POINT_BASE);
    }

    // @inheritdoc IUsd0PP
    function calculateAdjustmentFactor(uint256 netOutflows, uint256 weeklyTarget)
        public
        pure
        returns (uint256)
    {
        if (netOutflows == 0) {
            return 0;
        } else if (netOutflows <= weeklyTarget) {
            // Φt = θt/θtarget,t (scaled by decimals for precision)
            return Math.mulDiv(netOutflows, SCALAR_ONE, weeklyTarget);
        }

        return SCALAR_ONE; // Max adjustment factor is 1 (scaled by decimals)
    }

    // @inheritdoc IUsd0PP
    function calculateNetOutflows(uint256 usd0ppAmount) public view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        uint256 currentDay = block.timestamp / 1 days;
        uint256 netInFlow = 0;
        uint256 netOutFlow = 0;

        for (uint256 i; i < USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS; ++i) {
            if (currentDay >= i) {
                netInFlow += $.dailyUsd0ppInflows[currentDay - i];
                netOutFlow += $.dailyUsd0ppOutflows[currentDay - i];
            }
        }

        // Return early if no net outflows
        return netOutFlow <= netInFlow ? usd0ppAmount : (netOutFlow - netInFlow) + usd0ppAmount;
    }

    // @inheritdoc IUsd0PP
    function calculateRequiredUsual(uint256 usd0ppAmount) public view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // Calculate adjustment factor based on net outflows vs target
        uint256 adjustmentFactor = calculateAdjustmentFactor(
            calculateNetOutflows(usd0ppAmount),
            calculateWeeklyTargetRedemptions(totalSupply(), $.targetRedemptionRate)
        );

        // Calculate required USUAL with all scaling factors using intermediate steps to prevent precision loss
        return Math.mulDiv(
            usd0ppAmount * $.durationCostFactor * adjustmentFactor,
            $.usualDistributionPerUsd0pp,
            SCALAR_ONE * SCALAR_ONE,
            Math.Rounding.Ceil
        );
    }

    /*//////////////////////////////////////////////////////////////
                             Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _update(address sender, address recipient, uint256 amount)
        internal
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        IUsd0 usd0 = IUsd0(address($.usd0));
        if (usd0.isBlacklisted(sender) || usd0.isBlacklisted(recipient)) {
            revert Blacklisted();
        }
        // we update the balance of the sender and the recipient
        super._update(sender, recipient, amount);
    }

    /// @notice Updates the daily USD0++ flow tracking
    /// @param amount The amount of USD0++ to track
    /// @param isInflow True if tracking inflow, false for outflow
    function _updateDailyUSD0pplFlow(uint256 amount, bool isInflow) internal {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        uint256 currentDay = block.timestamp / 1 days;

        // Update today's flow
        if (isInflow) {
            $.dailyUsd0ppInflows[currentDay] += amount;
            emit DailyUsd0ppInflowUpdated(currentDay, amount);
        } else {
            $.dailyUsd0ppOutflows[currentDay] += amount;
            emit DailyUsd0ppOutflowUpdated(currentDay, amount);
        }
    }

    /// @notice Burns a specified amount of USD0++ tokens from an account and updates the daily USD0++ flow tracking
    /// @param account The address of the account to burn tokens from
    /// @param amount The amount of USD0++ tokens to burn
    function _burnAndUpdateFlow(address account, uint256 amount) internal {
        super._burn(account, amount);
        _updateDailyUSD0pplFlow(amount, false);
    }
}
