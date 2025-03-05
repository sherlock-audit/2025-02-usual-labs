# Usual Labs contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Arbitrum. 

https://tech.usual.money/smart-contracts/contract-deployments
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

### Contracts without initializers: If you find a contract without an initializer that appears to need one, please note that:

- The initializer was likely intentionally removed to avoid bloating contracts
 - These contracts are typically in the mock directory
 - Their usage can be verified in the test files

### Contracts with unexecuted initializers: For contracts that still have initializers that haven't been executed:

Please verify the default values to ensure they're appropriate
 - Only in these cases should you flag an issue

In a nutshell, the absence of an initializer is generally not an issue worth reporting unless it is present and there is issue in it

------- Regarding Findings/Severity ( TVL is assumed at ONE BILLION USD ) -------


Severity Matrix for Core Stablecoin Protocol + RWA Token Wrapper Contracts ( UsualUSDtB, UsualM)

Contracts + imported files
USD0
USD0PP
DaoCollateral
RegistryAccess
RegistryContract
ClassicalOracle minus UsualOracle
SwapperEngine 
UsualUSDtB
UsualM


High
An issue that results in the loss, theft, waste, or permanent freezing of 5%-100% of the total TVL.  

Medium
An issue that results in the loss, theft, waste, or permanent freezing of 0.5%-5% of the total TVL.
An issue that results in the theft of 0.01%-5% of the total TVL.

Out of Scope:
Issues that can be remedied by RWA Token Governance / Usual Token Governance burning and minting (e.g. frozen assets after an attack) are out of scope.

Severity Matrix for Usual Token & Distribution Module, UsualX, Usual*, Airdrop ( everything outside of the files above)

High findings here aren't considered in unlocking the high pot. 50% of the finding value of Core Protocol/Wrapper

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


