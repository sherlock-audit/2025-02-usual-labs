# Usual Labs contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Arbitrum. 

https://tech.usual.money/smart-contracts/contract-deployments
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
The token contracts used in each repository are known in advance and there is no use of arbitrary tokens in any contracts.

We are currently supporting as RWAs Tokens:

USYC by Hashnote UsualM , wrapping smartM (aka wrappedM) by M^0 eUSD0 ( OUT OF SCOPE!)

We are going to support UsualUSDtB, wrapping USDtB by Ethena

Any future RWA's are implied to follow similar specs as the ones above.

For the SwapperEngine, we are using USDC by Circle.

Issues stemming from potential different future implementations of these Tokens are out of scope.

Any behaviour from the Tokencontracts above is intentional and do not qualify as attack vectors.

There is no need to analyze potential use/integration of any other token code (which could potentially have weird behaviour) in any of the modules.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
No.
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No.
___

### Q: Is the codebase expected to comply with any specific EIPs?
We not consider compliance to EIP's relevant unless they pose an attack vector.
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
N/A
___

### Q: Please provide links to previous audits (if any).
https://tech.usual.money/security-and-audits/audits
Previous Sherlock audit Euler EVK & UsualUSDtB reports, plus two additional audit reports to be added until finalization ( latest 26/02/2025) 
___

### Q: Please list any relevant protocol resources.
Gitbook: https://tech.usual.money/
Architecture Diagram: https://tech.usual.money/overview/architecture ( to be updated with usualM)
Whitepaper: https://docs.usual.money/resources-and-ecosystem/whitepaper



___

### Q: Additional audit information.
If there is no Proof of Concept or equivalent proof added, findings are not accepted.

RWA Tokenizer Risk ( oracles etc.) out of scope (including `min/maxAnswer` checks on Chainlink).

Malicious bridges (layerzero/chainlink) out of scope.

Curve Protocol is out of scope.

Multisignature wallet hacks.

No natspec/comments/harness/mocks/outdated documentation files in code repository count as findings.

Economical attacks only if they are at minimum symmetric (e.g. I spend $1 to gain at least $1).

Bugs or incorrect behavior in third party code like RWA token implementations or other protocols are out of scope.

Incorrect data supplied by third party oracles.

Issues related to deploy scripts or tests.

Any vulnerability acknowledged or not acknowledged and not fixed by the protocol team (previous audit&competition reports) is invalid.

Attacks which include calls to permissioned smart contract functions or requires the attacker to hold a specific role in the Usual protocol are out of scope.

Design choices related to the protocol are out of scope.

Extreme market turmoil vulnerability are out of scope.

Brute force attacks are out of scope.

Tokens/Tokentypes that are not not actually used by the Usual Protocol yet are out of scope. 

Any type of user errors, like transfers to address(0), that can be easily prevented in the frontend
issues based on Sybil attacks out of scope.

Issues related to centralization risks are out of scope.

Issues related to SwapperEngine if the underlying isn't USDC / Circle is compromised are out of scope.


In this contest, issues found in specific smart contracts are considered **high-priority** and will be rewarded at the standard payout rates. These contracts are:  

- **USD0**  
- **USD0PP**  
- **DaoCollateral**  
- **RegistryAccess**  
- **RegistryContract**  
- **ClassicalOracle** (excluding **UsualOracle**)  
- **SwapperEngine**  
- **UsualUSDtB**  
- **UsualM**  

Issues found in any **other contracts** outside of this list are still valuable but will receive **adjusted payouts**:  

- **Medium-severity issues** in these contracts will be rewarded at **50% of a Medium payout**(choose Medium Unimportant severity)  
- **High-severity issues** in these contracts will be rewarded at **50% of a High payout**(choose High Unimportant severity)

Additionally, this contest features an **unlocking prize pool**, which is determined by the severity of the issues found:  

- **$80,000** if no Medium or High-severity issues are found in high-priority contracts.  
- **$100,000** if at least one Medium-severity issue is found in a high-priority contract **or** if a High-severity issue is found in a low-priority contract.  
- **$200,000** if at least one High-severity issue is found in a high-priority contract.  

To unlock the higher prize pool, the Medium or High-severity issue **must be found in a high-priority contract**—except for the **$100,000 tier**, which can also be unlocked by a High-severity issue in a low-priority contract. If only Medium-severity issues are found in lower-priority contracts, the prize pool will **not** be unlocked, and the **$80,000** will be split fully among the auditors who reported those issues.  

The general rule is that an issue must **impact the functionality** of one of the high-priority contracts to receive full rewards and contribute toward unlocking the highest prize pool.


------- Regarding Findings/Severity ( TVL is assumed at ONE BILLION USD ) -------

Severity Matrix for Core Stablecoin Protocol + RWA Token Wrapper Contracts ( UsualUSDtB, UsualM)

High
An issue that results in the loss, theft, waste, or permanent freezing of 5%-100% of the total TVL.  

Medium
An issue that results in the loss, theft, waste, or permanent freezing of 0.5%-5% of the total TVL.
An issue that results in the theft of 0.01%-5% of the total TVL.

Out of Scope:
Issues that can be remedied by RWA Token Governance / Usual Token Governance burning and minting (e.g. frozen assets after an attack) are out of scope.

Severity Matrix for Usual Token & Distribution Module, UsualX, Usual*, Airdrop ( everything outside of the files above)

High
An issue that results in the theft of 10%-100% of the current Usual supply. 

Medium
An issue that results in the theft of 5%-10% of the current Usual supply. 


----- REGARDING FINDINGS ON DEPLOYED CONTRACTS -----

Any vulnerability involving already deployed core contracts must not be disclosed publicly or to any other person, entity or email address before Usual Labs has been notified, has fixed the issue, and has granted permission for disclosure in the competition. In addition, disclosure must be made within 24 hours following discovery of the vulnerability. Additional compensation outside of the competition prize pool can also be granted optionally by Usual Labs.




# Audit scope

[pegasus @ f567a2f6ec952b8f277cc33f807ee9ed555715d9](https://github.com/usual-dao/pegasus/tree/f567a2f6ec952b8f277cc33f807ee9ed555715d9)
- [pegasus/packages/solidity/shared/MarketParamsLib.sol](pegasus/packages/solidity/shared/MarketParamsLib.sol)
- [pegasus/packages/solidity/shared/interfaces/curve/ICurveFactory.sol](pegasus/packages/solidity/shared/interfaces/curve/ICurveFactory.sol)
- [pegasus/packages/solidity/shared/interfaces/curve/ICurvePool.sol](pegasus/packages/solidity/shared/interfaces/curve/ICurvePool.sol)
- [pegasus/packages/solidity/shared/interfaces/morpho/IMorpho.sol](pegasus/packages/solidity/shared/interfaces/morpho/IMorpho.sol)
- [pegasus/packages/solidity/shared/interfaces/morpho/IOracle.sol](pegasus/packages/solidity/shared/interfaces/morpho/IOracle.sol)
- [pegasus/packages/solidity/src/L2/token/L2Usd0.sol](pegasus/packages/solidity/src/L2/token/L2Usd0.sol)
- [pegasus/packages/solidity/src/L2/token/L2Usd0PP.sol](pegasus/packages/solidity/src/L2/token/L2Usd0PP.sol)
- [pegasus/packages/solidity/src/TokenMapping.sol](pegasus/packages/solidity/src/TokenMapping.sol)
- [pegasus/packages/solidity/src/airdrop/AirdropDistribution.sol](pegasus/packages/solidity/src/airdrop/AirdropDistribution.sol)
- [pegasus/packages/solidity/src/airdrop/AirdropTaxCollector.sol](pegasus/packages/solidity/src/airdrop/AirdropTaxCollector.sol)
- [pegasus/packages/solidity/src/airdrop/README.md](pegasus/packages/solidity/src/airdrop/README.md)
- [pegasus/packages/solidity/src/constants.sol](pegasus/packages/solidity/src/constants.sol)
- [pegasus/packages/solidity/src/daoCollateral/DaoCollateral.sol](pegasus/packages/solidity/src/daoCollateral/DaoCollateral.sol)
- [pegasus/packages/solidity/src/distribution/DistributionModule.sol](pegasus/packages/solidity/src/distribution/DistributionModule.sol)
- [pegasus/packages/solidity/src/errors.sol](pegasus/packages/solidity/src/errors.sol)
- [pegasus/packages/solidity/src/interfaces/IDaoCollateral.sol](pegasus/packages/solidity/src/interfaces/IDaoCollateral.sol)
- [pegasus/packages/solidity/src/interfaces/IDistributor.sol](pegasus/packages/solidity/src/interfaces/IDistributor.sol)
- [pegasus/packages/solidity/src/interfaces/ISwapperEngine.sol](pegasus/packages/solidity/src/interfaces/ISwapperEngine.sol)
- [pegasus/packages/solidity/src/interfaces/airdrop/IAirdropDistribution.sol](pegasus/packages/solidity/src/interfaces/airdrop/IAirdropDistribution.sol)
- [pegasus/packages/solidity/src/interfaces/airdrop/IAirdropTaxCollector.sol](pegasus/packages/solidity/src/interfaces/airdrop/IAirdropTaxCollector.sol)
- [pegasus/packages/solidity/src/interfaces/curve/IGauge.sol](pegasus/packages/solidity/src/interfaces/curve/IGauge.sol)
- [pegasus/packages/solidity/src/interfaces/distribution/IDistributionAllocator.sol](pegasus/packages/solidity/src/interfaces/distribution/IDistributionAllocator.sol)
- [pegasus/packages/solidity/src/interfaces/distribution/IDistributionModule.sol](pegasus/packages/solidity/src/interfaces/distribution/IDistributionModule.sol)
- [pegasus/packages/solidity/src/interfaces/distribution/IDistributionOperator.sol](pegasus/packages/solidity/src/interfaces/distribution/IDistributionOperator.sol)
- [pegasus/packages/solidity/src/interfaces/distribution/IOffChainDistributionChallenger.sol](pegasus/packages/solidity/src/interfaces/distribution/IOffChainDistributionChallenger.sol)
- [pegasus/packages/solidity/src/interfaces/oracles/IAggregator.sol](pegasus/packages/solidity/src/interfaces/oracles/IAggregator.sol)
- [pegasus/packages/solidity/src/interfaces/oracles/IDataPublisher.sol](pegasus/packages/solidity/src/interfaces/oracles/IDataPublisher.sol)
- [pegasus/packages/solidity/src/interfaces/oracles/IOracle.sol](pegasus/packages/solidity/src/interfaces/oracles/IOracle.sol)
- [pegasus/packages/solidity/src/interfaces/registry/IRegistryAccess.sol](pegasus/packages/solidity/src/interfaces/registry/IRegistryAccess.sol)
- [pegasus/packages/solidity/src/interfaces/registry/IRegistryContract.sol](pegasus/packages/solidity/src/interfaces/registry/IRegistryContract.sol)
- [pegasus/packages/solidity/src/interfaces/token/IERC677.sol](pegasus/packages/solidity/src/interfaces/token/IERC677.sol)
- [pegasus/packages/solidity/src/interfaces/token/IERC677Receiver.sol](pegasus/packages/solidity/src/interfaces/token/IERC677Receiver.sol)
- [pegasus/packages/solidity/src/interfaces/token/IL2Usd0.sol](pegasus/packages/solidity/src/interfaces/token/IL2Usd0.sol)
- [pegasus/packages/solidity/src/interfaces/token/IL2Usd0PP.sol](pegasus/packages/solidity/src/interfaces/token/IL2Usd0PP.sol)
- [pegasus/packages/solidity/src/interfaces/token/IRwaMock.sol](pegasus/packages/solidity/src/interfaces/token/IRwaMock.sol)
- [pegasus/packages/solidity/src/interfaces/token/IUsd0.sol](pegasus/packages/solidity/src/interfaces/token/IUsd0.sol)
- [pegasus/packages/solidity/src/interfaces/token/IUsd0PP.sol](pegasus/packages/solidity/src/interfaces/token/IUsd0PP.sol)
- [pegasus/packages/solidity/src/interfaces/token/IUsual.sol](pegasus/packages/solidity/src/interfaces/token/IUsual.sol)
- [pegasus/packages/solidity/src/interfaces/token/IUsualS.sol](pegasus/packages/solidity/src/interfaces/token/IUsualS.sol)
- [pegasus/packages/solidity/src/interfaces/token/IUsualSP.sol](pegasus/packages/solidity/src/interfaces/token/IUsualSP.sol)
- [pegasus/packages/solidity/src/interfaces/tokenManager/ITokenMapping.sol](pegasus/packages/solidity/src/interfaces/tokenManager/ITokenMapping.sol)
- [pegasus/packages/solidity/src/interfaces/vaults/IUsualX.sol](pegasus/packages/solidity/src/interfaces/vaults/IUsualX.sol)
- [pegasus/packages/solidity/src/mock/ChainlinkMock.sol](pegasus/packages/solidity/src/mock/ChainlinkMock.sol)
- [pegasus/packages/solidity/src/mock/ERC20Whitelist.sol](pegasus/packages/solidity/src/mock/ERC20Whitelist.sol)
- [pegasus/packages/solidity/src/mock/IPayable.sol](pegasus/packages/solidity/src/mock/IPayable.sol)
- [pegasus/packages/solidity/src/mock/IRwaFactory.sol](pegasus/packages/solidity/src/mock/IRwaFactory.sol)
- [pegasus/packages/solidity/src/mock/MockAggregator.sol](pegasus/packages/solidity/src/mock/MockAggregator.sol)
- [pegasus/packages/solidity/src/mock/SwapperEngine/SwapperEngineHarness.sol](pegasus/packages/solidity/src/mock/SwapperEngine/SwapperEngineHarness.sol)
- [pegasus/packages/solidity/src/mock/constants.sol](pegasus/packages/solidity/src/mock/constants.sol)
- [pegasus/packages/solidity/src/mock/daoCollateral/DaoCollateralHarness.sol](pegasus/packages/solidity/src/mock/daoCollateral/DaoCollateralHarness.sol)
- [pegasus/packages/solidity/src/mock/dataPublisher.sol](pegasus/packages/solidity/src/mock/dataPublisher.sol)
- [pegasus/packages/solidity/src/mock/distribution/DistributionModuleHarness.sol](pegasus/packages/solidity/src/mock/distribution/DistributionModuleHarness.sol)
- [pegasus/packages/solidity/src/mock/errors.sol](pegasus/packages/solidity/src/mock/errors.sol)
- [pegasus/packages/solidity/src/modules/RewardAccrualBase.sol](pegasus/packages/solidity/src/modules/RewardAccrualBase.sol)
- [pegasus/packages/solidity/src/oracles/AbstractOracle.sol](pegasus/packages/solidity/src/oracles/AbstractOracle.sol)
- [pegasus/packages/solidity/src/oracles/ClassicalOracle.sol](pegasus/packages/solidity/src/oracles/ClassicalOracle.sol)
- [pegasus/packages/solidity/src/oracles/UsualOracle.sol](pegasus/packages/solidity/src/oracles/UsualOracle.sol)
- [pegasus/packages/solidity/src/registry/RegistryAccess.sol](pegasus/packages/solidity/src/registry/RegistryAccess.sol)
- [pegasus/packages/solidity/src/registry/RegistryContract.sol](pegasus/packages/solidity/src/registry/RegistryContract.sol)
- [pegasus/packages/solidity/src/swapperEngine/SwapperEngine.sol](pegasus/packages/solidity/src/swapperEngine/SwapperEngine.sol)
- [pegasus/packages/solidity/src/token/Usd0.sol](pegasus/packages/solidity/src/token/Usd0.sol)
- [pegasus/packages/solidity/src/token/Usd0PP.sol](pegasus/packages/solidity/src/token/Usd0PP.sol)
- [pegasus/packages/solidity/src/token/Usual.sol](pegasus/packages/solidity/src/token/Usual.sol)
- [pegasus/packages/solidity/src/token/UsualS.sol](pegasus/packages/solidity/src/token/UsualS.sol)
- [pegasus/packages/solidity/src/token/UsualSP.sol](pegasus/packages/solidity/src/token/UsualSP.sol)
- [pegasus/packages/solidity/src/utils/CheckAccessControl.sol](pegasus/packages/solidity/src/utils/CheckAccessControl.sol)
- [pegasus/packages/solidity/src/utils/NoncesUpgradeable.sol](pegasus/packages/solidity/src/utils/NoncesUpgradeable.sol)
- [pegasus/packages/solidity/src/utils/merkleTree/README.md](pegasus/packages/solidity/src/utils/merkleTree/README.md)
- [pegasus/packages/solidity/src/utils/merkleTree/generateAirdropMerkleProof.js](pegasus/packages/solidity/src/utils/merkleTree/generateAirdropMerkleProof.js)
- [pegasus/packages/solidity/src/utils/merkleTree/generateAirdropMerkleRoot.js](pegasus/packages/solidity/src/utils/merkleTree/generateAirdropMerkleRoot.js)
- [pegasus/packages/solidity/src/utils/merkleTree/generateDistributionMerkleProof.js](pegasus/packages/solidity/src/utils/merkleTree/generateDistributionMerkleProof.js)
- [pegasus/packages/solidity/src/utils/merkleTree/generateDistributionMerkleRoot.js](pegasus/packages/solidity/src/utils/merkleTree/generateDistributionMerkleRoot.js)
- [pegasus/packages/solidity/src/utils/normalize.sol](pegasus/packages/solidity/src/utils/normalize.sol)
- [pegasus/packages/solidity/src/vaults/UsualX.sol](pegasus/packages/solidity/src/vaults/UsualX.sol)
- [pegasus/packages/solidity/src/vaults/YieldBearingVault.sol](pegasus/packages/solidity/src/vaults/YieldBearingVault.sol)

[usual-usdtb @ 688a9206ca858db47ce2e668fd6a4683e8434bcb](https://github.com/usual-dao/usual-usdtb/tree/688a9206ca858db47ce2e668fd6a4683e8434bcb)
- [usual-usdtb/src/constants.sol](usual-usdtb/src/constants.sol)
- [usual-usdtb/src/oracle/NAVProxyUSDTBPriceFeed.sol](usual-usdtb/src/oracle/NAVProxyUSDTBPriceFeed.sol)
- [usual-usdtb/src/usual/UsualUsdtb.sol](usual-usdtb/src/usual/UsualUsdtb.sol)
- [usual-usdtb/src/usual/interfaces/IRegistryAccess.sol](usual-usdtb/src/usual/interfaces/IRegistryAccess.sol)
- [usual-usdtb/src/usual/interfaces/IUsdtb.sol](usual-usdtb/src/usual/interfaces/IUsdtb.sol)
- [usual-usdtb/src/usual/interfaces/IUsualUSDTB.sol](usual-usdtb/src/usual/interfaces/IUsualUSDTB.sol)

[usual-m @ 5f9b256a103ac91aa0605507d94b8766ae8601d3](https://github.com/m0-foundation/usual-m/tree/5f9b256a103ac91aa0605507d94b8766ae8601d3)
- [usual-m/src/oracle/AggregatorV3Interface.sol](usual-m/src/oracle/AggregatorV3Interface.sol)
- [usual-m/src/oracle/NAVProxyMPriceFeed.sol](usual-m/src/oracle/NAVProxyMPriceFeed.sol)
- [usual-m/src/usual/UsualM.sol](usual-m/src/usual/UsualM.sol)
- [usual-m/src/usual/constants.sol](usual-m/src/usual/constants.sol)
- [usual-m/src/usual/interfaces/IRegistryAccess.sol](usual-m/src/usual/interfaces/IRegistryAccess.sol)
- [usual-m/src/usual/interfaces/IUsualM.sol](usual-m/src/usual/interfaces/IUsualM.sol)
- [usual-m/src/usual/interfaces/IWrappedMLike.sol](usual-m/src/usual/interfaces/IWrappedMLike.sol)


