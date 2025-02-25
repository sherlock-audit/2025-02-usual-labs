// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

/* Roles */
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant PAUSING_CONTRACTS_ROLE = keccak256("PAUSING_CONTRACTS_ROLE");
bytes32 constant EARLY_BOND_UNLOCK_ROLE = keccak256("EARLY_BOND_UNLOCK_ROLE");
bytes32 constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");
bytes32 constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
bytes32 constant WITHDRAW_FEE_UPDATER_ROLE = keccak256("WITHDRAW_FEE_UPDATER_ROLE");
bytes32 constant FEE_SWEEPER_ROLE = keccak256("FEE_SWEEPER_ROLE");
bytes32 constant BURN_RATIO_UPDATER_ROLE = keccak256("BURN_RATIO_UPDATER_ROLE");
bytes32 constant FLOOR_PRICE_UPDATER_ROLE = keccak256("FLOOR_PRICE_UPDATER_ROLE");
bytes32 constant DAO_COLLATERAL = keccak256("DAO_COLLATERAL_CONTRACT");
bytes32 constant USUALSP = keccak256("USUALSP_CONTRACT");
bytes32 constant USD0_MINT = keccak256("USD0_MINT");
bytes32 constant USD0_BURN = keccak256("USD0_BURN");
bytes32 constant USD0PP_MINT = keccak256("USD0PP_MINT");
bytes32 constant USD0PP_BURN = keccak256("USD0PP_BURN");
bytes32 constant USUALS_BURN = keccak256("USUALS_BURN");
bytes32 constant USUAL_MINT = keccak256("USUAL_MINT");
bytes32 constant USUAL_BURN = keccak256("USUAL_BURN");
bytes32 constant INTENT_MATCHING_ROLE = keccak256("INTENT_MATCHING_ROLE");
bytes32 constant NONCE_THRESHOLD_SETTER_ROLE = keccak256("NONCE_THRESHOLD_SETTER_ROLE");
bytes32 constant PEG_MAINTAINER_ROLE = keccak256("PEG_MAINTAINER_ROLE");
bytes32 constant PEG_MAINTAINER_UNLIMITED_ROLE = keccak256("PEG_MAINTAINER_UNLIMITED_ROLE");
bytes32 constant USD0PP_CAPPED_UNWRAP_ROLE = keccak256("USD0PP_CAPPED_UNWRAP_ROLE");
bytes32 constant UNWRAP_CAP_ALLOCATOR_ROLE = keccak256("UNWRAP_CAP_ALLOCATOR_ROLE");
bytes32 constant SWAPPER_ENGINE = keccak256("SWAPPER_ENGINE");
bytes32 constant INTENT_TYPE_HASH = keccak256(
    "SwapIntent(address recipient,address rwaToken,uint256 amountInTokenDecimals,uint256 nonce,uint256 deadline)"
);
bytes32 constant DISTRIBUTION_ALLOCATOR_ROLE = keccak256("DISTRIBUTION_ALLOCATOR_ROLE");
bytes32 constant DISTRIBUTION_OPERATOR_ROLE = keccak256("DISTRIBUTION_OPERATOR_ROLE");
bytes32 constant DISTRIBUTION_CHALLENGER_ROLE = keccak256("DISTRIBUTION_CHALLENGER_ROLE");
bytes32 constant USD0PP_USUAL_DISTRIBUTION_ROLE = keccak256("USD0PP_USUAL_DISTRIBUTION_ROLE");
bytes32 constant USD0PP_DURATION_COST_FACTOR_ROLE = keccak256("USD0PP_DURATION_COST_FACTOR_ROLE");
bytes32 constant USD0PP_TREASURY_ALLOCATION_RATE_ROLE =
    keccak256("USD0PP_TREASURY_ALLOCATION_RATE_ROLE");
bytes32 constant USD0PP_TARGET_REDEMPTION_RATE_ROLE =
    keccak256("USD0PP_TARGET_REDEMPTION_RATE_ROLE");
/* Airdrop Roles */
bytes32 constant AIRDROP_OPERATOR_ROLE = keccak256("AIRDROP_OPERATOR_ROLE");
bytes32 constant AIRDROP_PENALTY_OPERATOR_ROLE = keccak256("AIRDROP_PENALTY_OPERATOR_ROLE");
bytes32 constant USUALSP_OPERATOR_ROLE = keccak256("USUALSP_OPERATOR_ROLE");

/* Contracts */
bytes32 constant CONTRACT_REGISTRY_ACCESS = keccak256("CONTRACT_REGISTRY_ACCESS");
bytes32 constant CONTRACT_DAO_COLLATERAL = keccak256("CONTRACT_DAO_COLLATERAL");
bytes32 constant CONTRACT_USD0PP = keccak256("CONTRACT_USD0PP");
bytes32 constant CONTRACT_USUALS = keccak256("CONTRACT_USUALS");
bytes32 constant CONTRACT_USUALSP = keccak256("CONTRACT_USUALSP");
bytes32 constant CONTRACT_TOKEN_MAPPING = keccak256("CONTRACT_TOKEN_MAPPING");
bytes32 constant CONTRACT_ORACLE = keccak256("CONTRACT_ORACLE");
bytes32 constant CONTRACT_ORACLE_USUAL = keccak256("CONTRACT_ORACLE_USUAL");
bytes32 constant CONTRACT_DATA_PUBLISHER = keccak256("CONTRACT_DATA_PUBLISHER");
bytes32 constant CONTRACT_TREASURY = keccak256("CONTRACT_TREASURY");
bytes32 constant CONTRACT_YIELD_TREASURY = keccak256("CONTRACT_YIELD_TREASURY");
bytes32 constant CONTRACT_SWAPPER_ENGINE = keccak256("CONTRACT_SWAPPER_ENGINE");
bytes32 constant CONTRACT_AIRDROP_DISTRIBUTION = keccak256("CONTRACT_AIRDROP_DISTRIBUTION");
bytes32 constant CONTRACT_AIRDROP_TAX_COLLECTOR = keccak256("CONTRACT_AIRDROP_TAX_COLLECTOR");
bytes32 constant CONTRACT_DISTRIBUTION_MODULE = keccak256("CONTRACT_DISTRIBUTION_MODULE");

/* Registry */
bytes32 constant CONTRACT_REGISTRY = keccak256("CONTRACT_REGISTRY"); // Not set on production

/* Contract tokens */
bytes32 constant CONTRACT_USD0 = keccak256("CONTRACT_USD0");
bytes32 constant CONTRACT_USUAL = keccak256("CONTRACT_USUAL");
bytes32 constant CONTRACT_USDC = keccak256("CONTRACT_USDC");
bytes32 constant CONTRACT_USUALX = keccak256("CONTRACT_USUALX");

/* Token names and symbols */
string constant USUALSSymbol = "USUAL*";
string constant USUALSName = "USUAL Star";

string constant USUALSymbol = "USUAL";
string constant USUALName = "USUAL";

string constant USUALXSymbol = "USUALX";
string constant USUALXName = "USUALX";

/* Constants */
uint256 constant INITIAL_ACCUMULATED_FEES = 0; // For now, we don't have any fees accumulated. This constant can be used to initialize the contract with the correct amount of fees.
uint256 constant INITIAL_SHARES_MINTING = 10_000e18; // For now, we mint "dead" shares has we started distribution early. This constant will be used to initialize the contract with the correct amount.
uint256 constant SCALAR_ONE = 1e18;
uint256 constant BPS_SCALAR = 10_000; // 10000 basis points = 100%
uint256 constant DISTRIBUTION_FREQUENCY_SCALAR = 1 days;

uint256 constant SCALAR_TEN_KWEI = 10_000;
uint256 constant MAX_REDEEM_FEE = 2500;
uint256 constant MINIMUM_USDC_PROVIDED = 100e6; //minimum of 100 USDC deposit;
// we take 12sec as the average block time
// 1 year = 3600sec * 24 hours * 365 days * 4 years  = 126_144_000 + 1 day // adding a leap day
uint256 constant BOND_DURATION_FOUR_YEAR = 126_230_400; //including a leap day;
uint256 constant USUAL_DISTRIBUTION_CHALLENGE_PERIOD = 1 weeks;
uint256 constant BASIS_POINT_BASE = 10_000;
uint256 constant INITIAL_BURN_RATIO_BPS = 3334;

uint256 constant VESTING_DURATION_THREE_YEARS = 94_608_000; // 3 years
uint256 constant USUALSP_VESTING_STARTING_DATE = 1_732_530_600; // Mon Nov 25 2024 10:30:00 GMT+0000
uint256 constant STARTDATE_USUAL_CLAIMING_USUALSP = 1_764_066_600; // Tue Nov 25 2025 10:30:00 GMT+0000

uint256 constant STARTDATE_USUAL_CLAIMING_DISTRIBUTION_MODULE = 1_734_516_000; // Dec 18 2024 10:00:00  GMT+0000
uint256 constant AIRDROP_INITIAL_START_TIME = 1_734_516_000; // Dec 18 2024 10:00:00  GMT+0000

uint256 constant AIRDROP_VESTING_DURATION_IN_MONTHS = 6;
uint256 constant ONE_YEAR = 31_536_000; // 365 days
uint256 constant SIX_MONTHS = 15_768_000;
uint256 constant ONE_MONTH = 2_628_000; // ONE_YEAR / 12 = 30,4 days
uint64 constant ONE_WEEK = 604_800;
uint256 constant NUMBER_OF_MONTHS_IN_THREE_YEARS = 36;
uint256 constant END_OF_EARLY_UNLOCK_PERIOD = 1_735_686_000; // 31st Dec 2024 23:00:00 GMT+0000
uint256 constant FIRST_AIRDROP_VESTING_CLAIMING_DATE = 1_737_194_400; // 18th Jan 2025 10:00:00 GMT+0000
uint256 constant SECOND_AIRDROP_VESTING_CLAIMING_DATE = 1_739_872_800; // 18th Feb 2025 10:00:00 GMT+0000
uint256 constant THIRD_AIRDROP_VESTING_CLAIMING_DATE = 1_742_292_000; // 18th Mar 2025 10:00:00 GMT+0000
uint256 constant FOURTH_AIRDROP_VESTING_CLAIMING_DATE = 1_744_970_400; // 18th Apr 2025 10:00:00 GMT+0000
uint256 constant FIFTH_AIRDROP_VESTING_CLAIMING_DATE = 1_747_562_400; // 18th May 2025 10:00:00 GMT+0000
uint256 constant SIXTH_AIRDROP_VESTING_CLAIMING_DATE = 1_750_240_800; // 18th Jun 2025 10:00:00 GMT+0000

uint256 constant INITIAL_FLOOR_PRICE = 999_500_000_000_000_000; // 1 USD0++ = 0.9995 USD0

/* UsualX initial withdraw fee */
uint256 constant USUALX_WITHDRAW_FEE = 1000; // in BPS 10%

/* Usual Distribution Bucket Distribution Shares */
uint256 constant LBT_DISTRIBUTION_SHARE = 3552;
uint256 constant LYT_DISTRIBUTION_SHARE = 1026; // USD0/USD0++ AND USD0/USDC summed up
uint256 constant IYT_DISTRIBUTION_SHARE = 0;
uint256 constant BRIBE_DISTRIBUTION_SHARE = 346;
uint256 constant ECO_DISTRIBUTION_SHARE = 0;
uint256 constant DAO_DISTRIBUTION_SHARE = 1620;
uint256 constant MARKET_MAKERS_DISTRIBUTION_SHARE = 0;
uint256 constant USUALX_DISTRIBUTION_SHARE = 1728;
uint256 constant USUALSTAR_DISTRIBUTION_SHARE = 1728;
uint256 constant INITIAL_BASE_GAMMA = 7894; // 78.94

uint256 constant ONE_USDC = 1e6;
uint256 constant MAX_25_PERCENT_WITHDRAW_FEE = 2500; // 25% fee
uint256 constant YIELD_PRECISION = 1 days;

uint256 constant USUALS_TOTAL_SUPPLY = 360_000_000e18;
uint256 constant PRICE_TIMEOUT = 7 days;

address constant SUSDE_CHAINLINK_PRICE_ORACLE = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
uint256 constant CHAINLINK_PRICE_SCALAR = 1e8;

/* Usual burn initial parameters */
uint256 constant INITIAL_USUAL_BURN_TREASURY_ALLOCATION_RATE = 6666; // 66.66% in basis points
uint256 constant INITIAL_USUAL_BURN_DURATION_COST_FACTOR = 180; // 180 days (6 months)
uint256 constant INITIAL_USUAL_BURN_TARGET_REDEMPTION_RATE = 30; // 0.3% in basis points
uint256 constant INITIAL_USUAL_BURN_USUAL_DISTRIBUTION_PER_USD0PP = 9e14; // 0.0009 Usual per USD0PP
uint256 constant USD0PP_NET_OUTFLOWS_ROLLING_WINDOW_DAYS = 7; // 7 days

/* Token Addresses */
address constant USYC = 0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b;
address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

/*
 * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
 * to return to using the Oracle oracle. 18-digit precision.
 */

uint256 constant INITIAL_MAX_DEPEG_THRESHOLD = 100;

/* Maximum number of RWA tokens that can be associated with USD0 */
uint256 constant MAX_RWA_COUNT = 10;

/* Curvepool Addresses */
address constant CURVE_POOL_USD0_USD0PP = 0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52;
int128 constant CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0 = 0;
int128 constant CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP = 1;

/* Airdrop */

uint256 constant AIRDROP_CLAIMING_PERIOD_LENGTH = 182 days;

/* Distribution */
uint256 constant RATE0 = 400; // 4.03% in basis points

/* Hexagate */
address constant HEXAGATE_PAUSER = 0x114644925eD9A6Ab20bF85f36F1a458DF181b57B;

/* Mainnet Usual Deployment */
address constant USUAL_MULTISIG_MAINNET = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;
address constant USUAL_PROXY_ADMIN_MAINNET = 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16;
address constant REGISTRY_CONTRACT_MAINNET = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
address constant USUALX_REDISTRIBUTION_CONTRACT = 0x351B2AFa5C8e5Ff0644Fef2bEE5cA2B8Df56715A;
address constant TREASURY_MAINNET = 0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7;
