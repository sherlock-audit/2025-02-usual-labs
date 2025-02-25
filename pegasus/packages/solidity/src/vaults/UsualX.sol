//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {EIP712Upgradeable} from
    "openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {Normalize} from "src/utils/normalize.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {YieldBearingVault} from "src/vaults/YieldBearingVault.sol";

import {
    CONTRACT_USUAL,
    CONTRACT_YIELD_TREASURY,
    CONTRACT_DISTRIBUTION_MODULE,
    DEFAULT_ADMIN_ROLE,
    BLACKLIST_ROLE,
    WITHDRAW_FEE_UPDATER_ROLE,
    PAUSING_CONTRACTS_ROLE,
    BASIS_POINT_BASE,
    MAX_25_PERCENT_WITHDRAW_FEE,
    YIELD_PRECISION,
    FEE_SWEEPER_ROLE,
    INITIAL_BURN_RATIO_BPS,
    BURN_RATIO_UPDATER_ROLE,
    USUALX_REDISTRIBUTION_CONTRACT
} from "src/constants.sol";

import {
    NotAuthorized,
    NullAddress,
    InsufficientSupply,
    InsufficientAssets,
    AmountTooBig,
    AmountIsZero,
    Blacklisted,
    SameValue,
    ZeroYieldAmount,
    StartTimeNotInFuture,
    CurrentTimeBeforePeriodFinish,
    EndTimeNotAfterStartTime,
    InsufficientAssetsForYield,
    StartTimeBeforePeriodFinish
} from "src/errors.sol";

contract UsualX is
    YieldBearingVault,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IUsual;
    using Normalize for uint256;
    using CheckAccessControl for IRegistryAccess;

    // Event emitted when an address is blacklisted
    // @param account The address that was blacklisted
    event Blacklist(address account);
    // Event emitted when an address is removed from the blacklist
    // @param account The address that was removed from the blacklist
    event UnBlacklist(address account);
    // Event emitted when the withdrawal fee is updated
    // @param newWithdrawFeeBps The new withdrawal fee in basis points
    event WithdrawFeeUpdated(uint256 newWithdrawFeeBps);
    // @notice Event emitted when fees are swept
    // @param collector The address receiving the fees
    // @param amount The amount of fees swept
    // @param amountBurned The amount of tokens burned
    event FeeSwept(address indexed collector, uint256 amount, uint256 amountBurned);
    // @notice Event emitted when the burn ratio is updated
    // @param newBurnRatioBps The new burn ratio in basis points
    event BurnRatioUpdated(uint256 newBurnRatioBps);

    //@custom:storage-location erc7201:usualX.storage.v0
    struct UsualXStorageV0 {
        /// @notice The fee charged on withdrawals
        uint256 withdrawFeeBps;
        /// @notice The RegistryAccess contract instance for role checks.
        IRegistryAccess registryAccess;
        /// @notice The RegistryContract instance for contract interactions.
        IRegistryContract registryContract;
        /// @notice The blacklisted users mapping
        mapping(address => bool) isBlacklisted;
        /// @notice The USUAL token address
        IUsual usualToken;
        /// @notice The accumulated withdrawal fees
        uint256 accumulatedFees;
        /// @notice The percentage of fees to burn when sweeping (in basis points)
        uint256 burnRatioBps;
    }

    // keccak256(abi.encode(uint256(keccak256("usualX.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant UsualXStorageV0Location =
        0xe34b7e189bdc1dc8307eb679fcc632f366df79571fb57039f593735b96795300;

    /// @notice Returns the storage struct of the contract.
    /// @return $ The pointer to the storage struct of the contract.
    function _usualXStorageV0() internal pure returns (UsualXStorageV0 storage $) {
        bytes32 position = UsualXStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with burn ratio.
    /// @param accumulatedFees_ The amount of already accumulated fees
    function initializeV1(uint256 accumulatedFees_, uint256 initialShares)
        external
        reinitializer(2)
    {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        if (initialShares == 0) {
            revert AmountIsZero();
        }
        if (totalSupply() > 0) {
            revert InsufficientSupply();
        }
        IERC20 _asset = IERC20(asset());
        if (_asset.balanceOf(address(this)) < initialShares) {
            revert InsufficientAssets();
        }

        uint256 currentBalance = _asset.balanceOf(address(this));

        // Transfer existing tokens to the redistribution contract minus the initial shares minted
        if (currentBalance > 0 && currentBalance > initialShares) {
            _asset.safeTransfer(USUALX_REDISTRIBUTION_CONTRACT, currentBalance - initialShares);
        }

        if (USUALX_REDISTRIBUTION_CONTRACT == address(0)) {
            revert NullAddress();
        }

        // Sanity check
        if (INITIAL_BURN_RATIO_BPS > BASIS_POINT_BASE) {
            revert AmountTooBig();
        }
        $.burnRatioBps = INITIAL_BURN_RATIO_BPS;
        $.usualToken = IUsual($.registryContract.getContract(CONTRACT_USUAL));
        $.accumulatedFees = accumulatedFees_;
        emit BurnRatioUpdated($.burnRatioBps);
        YieldDataStorage storage y = _getYieldDataStorage();
        // mint dead shares to the vault
        y.totalDeposits = initialShares;
        _mint(address(this), initialShares);

        // clear and active yield period to get ready for the first yield distribution
        y.periodFinish = 0;
        y.yieldRate = 0;
        y.periodStart = 0;
        y.lastUpdateTime = 0;
        y.isActive = false;
    }

    /// @notice Pauses the contract.
    /// @dev Can be called by the pauser to pause some contract operations.
    function pause() external {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Can be called by the admin to unpause some contract operations.
    function unpause() external {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @notice  Adds an address to the blacklist.
    /// @dev     Can only be called by the admin.
    /// @param   account  The address to be blacklisted.
    function blacklist(address account) external {
        if (account == address(0)) {
            revert NullAddress();
        }
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if ($.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = true;

        emit Blacklist(account);
    }

    /// @notice  Removes an address from the blacklist.
    /// @dev     Can only be called by the admin.
    /// @param   account  The address to be removed from the blacklist.
    function unBlacklist(address account) external {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if (!$.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = false;

        emit UnBlacklist(account);
    }

    /// @notice Checks if an address is blacklisted.
    /// @param account The address to check.
    /// @return bool True if the address is blacklisted.
    function isBlacklisted(address account) external view returns (bool) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        return $.isBlacklisted[account];
    }

    /// @notice Hook that ensures token transfers are not made from or to not blacklisted addresses.
    /// @param from The address sending the tokens.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens being transferred.
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable)
    {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
            revert Blacklisted();
        }
        super._update(from, to, amount);
    }

    /// @notice Starts a new yield distribution period
    /// @dev Can only be called by the distribution contract
    /// @param yieldAmount The amount of yield to distribute
    /// @param startTime The start time of the new yield period
    /// @param endTime The end time of the new yield period
    function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        external
    {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        if (msg.sender != $.registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE)) {
            revert NotAuthorized();
        }
        _startYieldDistribution(yieldAmount, startTime, endTime);
    }

    /// @notice Starts a new yield distribution period
    /// @dev Can only be called by the distribution contract
    /// @param yieldAmount The amount of yield to distribute
    /// @param startTime The start time of the new yield period
    /// @param endTime The end time of the new yield period
    function _startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        internal
        override
    {
        YieldDataStorage storage $ = _getYieldDataStorage();
        IERC20 _asset = IERC20(asset());
        if (yieldAmount == 0) {
            revert ZeroYieldAmount();
        }
        if (startTime < block.timestamp) {
            revert StartTimeNotInFuture();
        }
        if (endTime <= startTime) {
            revert EndTimeNotAfterStartTime();
        }
        if (startTime < $.periodFinish) {
            revert StartTimeBeforePeriodFinish();
        }
        if (block.timestamp < $.periodFinish) {
            revert CurrentTimeBeforePeriodFinish();
        }
        _updateYield();

        uint256 periodDuration = endTime - startTime;
        uint256 newYieldRate =
            Math.mulDiv(yieldAmount, YIELD_PRECISION, periodDuration, Math.Rounding.Floor);

        if (_asset.balanceOf(address(this)) < $.totalDeposits + yieldAmount) {
            revert InsufficientAssetsForYield();
        }

        $.yieldRate = newYieldRate;
        $.periodStart = startTime;
        $.periodFinish = endTime;
        $.lastUpdateTime = startTime;
        $.isActive = true;
    }

    /// @notice Updates the withdrawal fee
    /// @dev Can only be called by addresses with WITHDRAW_FEE_UPDATER_ROLE
    /// @param newWithdrawFeeBps The new withdrawal fee in basis points
    function updateWithdrawFee(uint256 newWithdrawFeeBps) external {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(WITHDRAW_FEE_UPDATER_ROLE);

        if (newWithdrawFeeBps > MAX_25_PERCENT_WITHDRAW_FEE) {
            revert AmountTooBig();
        }

        $.withdrawFeeBps = newWithdrawFeeBps;
        emit WithdrawFeeUpdated(newWithdrawFeeBps);
    }

    /// @notice Returns the withdrawal fee in basis points
    /// @return The withdrawal fee in basis points
    function withdrawFeeBps() public view returns (uint256) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        return $.withdrawFeeBps;
    }

    /**
     * @dev Deposits assets with permit from msg.sender and mints shares to receiver.
     * @param assets The amount of assets to deposit.
     * @param receiver The address receiving the shares.
     * @param deadline The deadline for the permit.
     * @param v The recovery id for the permit.
     * @param r The r value for the permit.
     * @param s The s value for the permit.
     * @return shares The amount of shares minted.
     */
    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        try IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s) {} // solhint-disable-line no-empty-blocks
            catch {} // solhint-disable-line no-empty-blocks

        return deposit(assets, receiver);
    }

    /**
     * @dev See {IERC4626-deposit}.
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        returns (uint256 shares)
    {
        return super.deposit(assets, receiver);
    }

    /**
     * @dev See {IERC4626-mint}.
     */
    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver,
     * with the withdrawal fee taken in addition.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address receiving the assets.
     * @param owner The address owning the shares.
     * @return shares The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        YieldDataStorage storage yieldStorage = _getYieldDataStorage();
        // Check withdrawal limit
        uint256 maxAssets = maxWithdraw(owner);
        // maxAssets take into account the fee
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        shares = previewWithdraw(assets);
        // we need to add the fee on the assets to know exactly the shares to burn
        // assets is 100% - fee% of the total assets
        uint256 fee = Math.mulDiv(
            assets, $.withdrawFeeBps, BASIS_POINT_BASE - $.withdrawFeeBps, Math.Rounding.Ceil
        );
        // Track the fee
        $.accumulatedFees += fee;
        // Perform withdrawal (exact assets to receiver)
        super._withdraw(_msgSender(), receiver, owner, assets, shares);
        // take the fee
        yieldStorage.totalDeposits -= fee;
    }

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver,
     * with the withdrawal fee already accounted for in the asset amount.
     * @param shares The amount of shares to redeem.
     * @param receiver The address receiving the assets.
     * @param owner The address owning the shares.
     * @return assets The amount of assets withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        YieldDataStorage storage yieldStorage = _getYieldDataStorage();

        // Check redemption limit
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        // Calculate assets after fee
        assets = previewRedeem(shares);
        uint256 assetsWithFee = convertToAssets(shares);
        uint256 fee = assetsWithFee - assets;

        // Track the fee
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.accumulatedFees += fee;

        // Perform redemption
        super._withdraw(_msgSender(), receiver, owner, assets, shares);

        // take the fee
        yieldStorage.totalDeposits -= fee;
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
     *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
     *   called
     *   in the same transaction.
     * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
     *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        // Calculate the fee based on the equivalent assets of these shares
        uint256 fee = Math.mulDiv(
            assets, $.withdrawFeeBps, BASIS_POINT_BASE - $.withdrawFeeBps, Math.Rounding.Ceil
        );
        // Calculate total assets needed, including fee
        uint256 assetsWithFee = assets + fee;
        // Convert the total assets (including fee) to shares
        shares = _convertToShares(assetsWithFee, Math.Rounding.Ceil);
    }

    /**
     * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return previewRedeem(balanceOf(owner));
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redemption at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        // Calculate the raw amount of assets for the given shares
        uint256 assetsWithFee = convertToAssets(shares);

        // Calculates the fee part of an amount `assets` that already includes fees.
        uint256 fee =
            Math.mulDiv(assetsWithFee, $.withdrawFeeBps, BASIS_POINT_BASE, Math.Rounding.Ceil);
        assets = assetsWithFee - fee;
    }

    /// @notice Sets the burn ratio for fee sweeping
    /// @dev Can only be called by BURN_RATIO_UPDATER_ROLE
    /// @param burnRatioBps The new burn ratio in basis points
    function setBurnRatio(uint256 burnRatioBps) external {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        $.registryAccess.onlyMatchingRole(BURN_RATIO_UPDATER_ROLE);

        if (burnRatioBps > BASIS_POINT_BASE) {
            revert AmountTooBig();
        }

        $.burnRatioBps = burnRatioBps;
        emit BurnRatioUpdated(burnRatioBps);
    }

    /// @notice Sweeps accumulated fees to the treasury yield contract
    /// @dev Can only be called by FEE_SWEEPER_ROLE
    function sweepFees() external nonReentrant {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        address yieldTreasury = $.registryContract.getContract(CONTRACT_YIELD_TREASURY);

        if (yieldTreasury == address(0)) {
            revert NullAddress();
        }

        $.registryAccess.onlyMatchingRole(FEE_SWEEPER_ROLE);

        uint256 feesToSweep = $.accumulatedFees;
        if (feesToSweep == 0) {
            revert AmountIsZero();
        }

        $.accumulatedFees = 0;

        uint256 burnAmount =
            Math.mulDiv(feesToSweep, $.burnRatioBps, BASIS_POINT_BASE, Math.Rounding.Floor);
        uint256 transferAmount = feesToSweep - burnAmount;

        IUsual usualToken = $.usualToken;

        if (burnAmount > 0) {
            usualToken.burn(burnAmount);
        }
        if (transferAmount > 0) {
            usualToken.safeTransfer(yieldTreasury, transferAmount);
        }

        emit FeeSwept(yieldTreasury, feesToSweep, burnAmount);
    }

    /// @notice Returns the current yield rate
    /// @return The yield rate
    function getYieldRate() external view returns (uint256) {
        YieldDataStorage storage $ = _getYieldDataStorage();
        return $.yieldRate;
    }

    /// @notice Returns the burn ratio for fee sweeping
    /// @return The burn ratio in basis points
    function getBurnRatio() external view returns (uint256) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        return $.burnRatioBps;
    }

    /// @notice Returns the accumulated fees
    /// @return The accumulated fees
    function getAccumulatedFees() external view returns (uint256) {
        UsualXStorageV0 storage $ = _usualXStorageV0();
        return $.accumulatedFees;
    }
}
