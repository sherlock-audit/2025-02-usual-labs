
# Usual Smart Contracts Deployment Guide

This directory contains scripts for upgrading the Usual Smart Contracts on Ethereum Mainnet and on the virtual testnet provided by Tenderly.

## Tenderly Mainnet Fork Upgrade Guide

This guide explains the steps to follow when calling the script inside the `TenderlyTestnetSetup.s.sol` to seed the deployer address and the dev. team with USUAL and USUAL* on the Tenderly testnet to provide user acceptance testing environment.

By following these steps, you can deploy the upgrade on the Ethereum mainnet with confidence.

### 1. **Create a Mainnet Fork on Tenderly**

   - Log in to your [Tenderly](https://tenderly.co/) account.
   - Navigate to the "Forks" section and create a new fork of the Ethereum mainnet.
   - Copy the admin fork URL provided by Tenderly.

### 2. **Seed the Deployer Address And Dev. Team**

   - Make sure the deployer addresse you are using is present in the Tenderly testnet setup script and then start the script with the admin fork url.

   ```sh
   forge clean && forge script scripts/deployment/TenderlyTestnetSetup.s.sol -f <YOUR_ADMIN_RPC_URL> --broadcast --slow --unlocked

   ```

### 3. **Run the Upgrade Scripts on Testnet**

   ```sh
   forge clean && forge script scripts/deployment/MainnetFork.s.sol -f <YOUR_ADMIN_RPC_URL> --verify --etherscan-api-key <TENDERLY_API_TOKEN> --verifier-url https://virtual.mainnet.rpc.tenderly.co/<ADMIN_RPC_GUID>/verify/etherscan --broadcast --slow --unlocked
   ```

The ADMIN_RPC_GUID is the GUID in the ADMIN_RPC_URL. (e.g: if the ADMIN_RPC_URL is https://virtual.mainnet.rpc.tenderly.co/**61206120-4799-7ee2-bf29-490655f14fd4** then the GUID is **61206120-4799-7ee2-bf29-490655f14fd4**)

### 4. **Run the Tenderly Testnet Setup Script again for seeding the newly deployed tokens with USUAL and USUAL***

```sh
      forge clean && forge script scripts/deployment/TenderlyTestnetSetup.s.sol -f <YOUR_ADMIN_RPC_URL> --broadcast --slow
```

## Mainnet Upgrade Guide

This guide explains the steps to follow when calling the script from P10 to P13 inside the `Upgrade.s.sol` to upgrade the Usual protocol on Ethereum mainnet to v1.0, it is expected that the Tenderly testnet setup has been ran before running this upgrade script.

It is designed to be called in a linear fashion by an unprivileged address, starting from P10 to P13 with manual intervention between each phase.

Previous upgrade phases can be found in the git history of the `Upgrade.s.sol` script.
Make sure the deployer address has enough ETH to cover the gas fees.

Consider making adjustments to the forge CLI command to fit your wallet and the RPC URL you are using.

More information on how to interact with the multisig safe can be found [here](https://www.notion.so/usualmoney/How-to-use-the-Safe-UI-to-upgrade-contracts-2c59adf4df23415bb17ca6a4a5e1f454).

### Setup

 - [ ] Is maintenance mode enabled?
 - [ ] Is the dApp paused?
 - [ ] Is the USD0 paused?
 - [ ] ...

### P14

This phase deploy the Usd0, DaoCollateral new contracts implementations (requires a subsequent governance intervention to upgrade the proxy). It also deploy the AirdropTaxCollector contract and initializes the proxy and transfer rights to the governance.

Note: SwapperEngine implementation has already been deployed at [0xF65B0C88F65D620ea325FfB1aD46A5bA8A6E57d3](https://etherscan.io/address/0xf65b0c88f65d620ea325ffb1ad46a5ba8a6e57d3)

#### Run the script

   ```sh
   forge clean && forge script scripts/deployment/Upgrade.s.sol:P14 -f <ETHEREUM_RPC_URL> --verify --etherscan-api-key <ETHERSCAN_API_KEY> --broadcast --slow
   ```


#### Safe Interaction (**required for proceeding with P15**)

USD0, DaoCollateral and SwapperEngine new contracts implementation require to be set and initialized by the proxy admin multisig safe(0xaaDa...Ca16), please follow the steps below:

1. Open the proxy admin safe
2. Enter the transaction as displayed in the logs
3. Wait for the transactions to be included and verify the transactions on etherscan

AirdropTaxCollector contract requires to be registered by the administration governance(0x6e9d...FB7), please follow the steps below:

1. Open the administration safe
2. Enter the transaction as displayed in the logs
3. Wait for the transactions to be included and verify the transactions on etherscan

More information on how to interact with the multisig safe can be found [here](https://www.notion.so/usualmoney/How-to-use-the-Safe-UI-to-upgrade-contracts-2c59adf4df23415bb17ca6a4a5e1f454).

### P15

This phase deploys the AirdropDistribution contract, initializes the proxy and transfer rights to the governance.

#### Run the script

```sh
forge clean && forge script scripts/deployment/Upgrade.s.sol:P15 -f <ETHEREUM_RPC_URL> --verify --etherscan-api-key <ETHERSCAN_API_KEY> --broadcast --slow
```

#### Safe Interaction (**required for proceeding with P16**)

AirdropDistribution contract require to be registered by the administration governance(0x6e9d...FB7), please follow the steps below:

1. Open the administration safe
2. Enter the transaction as displayed in the logs
3. Wait for the transactions to be included and verify the transactions on etherscan

More information on how to interact with the multisig safe can be found [here](https://www.notion.so/usualmoney/How-to-use-the-Safe-UI-to-upgrade-contracts-2c59adf4df23415bb17ca6a4a5e1f454).


### P16

Note this phase is dependant of the inclusion of [#2014](https://github.com/usual-dao/pegasus/pull/2014) in the pegasus repo develop branch.

This phase deploys the UsualX new contract implementation.

#### Run the script

```sh
forge clean && forge script scripts/deployment/Upgrade.s.sol:P16 -f <ETHEREUM_RPC_URL> --verify --etherscan-api-key <ETHERSCAN_API_KEY> --broadcast --slow
```

#### Safe Interaction

UsualX new contract implementation requires to be set and reinitialized by the proxy admin multisig safe(0xaaDa...Ca16), please follow the steps below:

1. Open the proxy admin safe
2. Enter the transaction as displayed in the logs
3. Wait for the transactions to be included and verify the transactions on etherscan

## Verification

Once you have deployed the upgrade on mainnet, before unpausing the protocol, you need to verify the deployment of the new implementations and the proxy.

After the script execution, fill and run the verify script with the newly deployed addresses. You have to update the new implementation addresses and the new proxy in the `Verification.s.sol` script if the deployer (0x10dcEb0D2717F0EfA9524D2109567526C9374B26) nonce increased (currently at 30, next transaction nonce shall be 31).

```sh
forge clean && forge script scripts/deployment/Verification.s.sol -f <YOUR_MAINNET_RPC_URL>
```

<details>
<pre>
== Logs ==
  ####################################################
  # Fetching addresses from Mainnet ContractRegistry #
  ####################################################
  Verifying Accounts Assigned the role: USD0_MINT
  Role verified for address 0xde6e1F680C4816446C8D515989E2358636A38b04
  Verifying Accounts Assigned the role: USD0_BURN
  Role verified for address 0xde6e1F680C4816446C8D515989E2358636A38b04
  Verifying Accounts Assigned the role: DEFAULT_ADMIN_ROLE
  Role verified for address 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7
  Verifying Accounts Assigned the role: INTENT_MATCHING_ROLE
  Role verified for address 0x422565b76e5C2E633C8456F106988F4Ec2cFb4EB
  Verifying Accounts Assigned the role: USUAL_BURN
  Role verified for address 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7
  Verifying Accounts Assigned the role: USUAL_MINT
  Role verified for address 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7
  Verifying Accounts Assigned the role: USUALS_BURN
  Role verified for address 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7
  Verifying Accounts Assigned the role: USUAL_MINT
  Role verified for address 0xeFC39e5d66F6DFdd9708D1f88a3EE3D4041181ef
  Verifying Accounts Assigned the role: USUAL_BURN
  Role verified for address 0x06B964d96f5dCF7Eae9d7C559B09EDCe244d4B8E
  Verifying Accounts Assigned the role: AIRDROP_OPERATOR_ROLE
  Role verified for address 0xFCa95E89535E628c0f2d03a5F0b5d7aDC16FBb32
  Verifying Accounts Assigned the role: AIRDROP_PENALTY_OPERATOR_ROLE
  Role verified for address 0xFCa95E89535E628c0f2d03a5F0b5d7aDC16FBb32
  ###################################################################
  # Verifying the owner of the admin contracts for proxy is correct #
  ###################################################################
  USD0 ProxyAdmin OK
  RegistryAccess ProxyAdmin OK
  RegistryContract ProxyAdmin OK
  TokenMappingProxyAdmin OK
  DaoCollateral ProxyAdmin OK
  ClassicalOracle ProxyAdmin OK
  SwapperEngine ProxyAdmin OK
  USD0++ ProxyAdmin OK
  AirdropTaxCollector ProxyAdmin OK
  AirdropDistribution ProxyAdmin OK
  DistributionModule ProxyAdmin OK
  UsualX ProxyAdmin OK
  Usual ProxyAdmin OK
  UsualS ProxyAdmin OK
  UsualSP ProxyAdmin OK
  ######################################################
  # Verifying the implementation addresses are what we expect #
  ######################################################
  USD0 implementation OK
  RegistryAccess implementation OK
  RegistryContract implementation OK
  TokenMapping implementation OK
  DaoCollateral implementation OK
  ClassicalOracle implementation OK
  SwapperEngine implementation OK
  USD0++ implementation OK
  AirdropTaxCollector implementation OK
  AirdropDistribution implementation OK
  DistributionModule implementation OK
  UsualX implementation OK
  Usual implementation OK
  UsualS implementation OK
  UsualSP implementation OK
  USD0 ProxyAdmin 0xC15091D3478296fD522B2807a9541578910DCC41 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  USUAL ProxyAdmin 0x430a2712cEFaaC8cb66E9cb29fF267CFcfA38a42 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  USD0++ ProxyAdmin 0x65A7042460932A8E7B6aA9C765c2BAE5F4535C22 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  UsualS ProxyAdmin 0xEdAa35E1Ef08D247977b85aADED5D4512b7EF518 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  UsualSP ProxyAdmin 0x6600798521D5E5eDA1106953A55BC96677d8176F owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  RegistryAccess ProxyAdmin 0x77C5d652423dAB9B271C47d3D69bF56819327af7 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  RegistryContract ProxyAdmin 0x5032c19821020f47abC8A75633d536e98CdFb5eC owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  TokenMapping ProxyAdmin 0xe78aAb16A75641F629C69acbEE0E58AC18e21340 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  DaoCollateral ProxyAdmin 0xC6b60cBCec7D9f98fdcDef6B9A611A955d7FeFD4 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  SwapperEngine ProxyAdmin 0x76Ef37555D7C5e2b095F05CF1687641F9b99cA27 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  ClassicalOracle ProxyAdmin 0xA28D5e20A56B1D5D15ADf61e8D3025068eAb33E3 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  AirdropTaxCollector ProxyAdmin 0xfd29C8f6Cf9aF09d8C11f36a642E2dCFa11bc33a owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  AirdropDistribution ProxyAdmin 0x57B62fBFAB23D736E1f9807af885C5d2bCbc3015 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
  DistributionModule ProxyAdmin 0x9e2bA7996e1B4320Dd8cc58D2285855f197125b2 owner: 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16
</pre>
</details>

### Code and Bytecode verification (optional)

   - Verify that the source code of the new implementation contract matches the source code on etherscan. If not you can use the forge verify-code command to verify the code.

   ```sh
   forge verify-code --rpc-url <RPC_URL> --etherscan-api-key <KEY>  <CONTRACT_ADDRESS_TO_VERIFY> <path>:<contractname> --watch
   ```

   - Verify that the bytecode of the new implementation contract matches the bytecode on etherscan.

   ```sh
   forge verify-bytecode --rpc-url <RPC_URL> --etherscan-api-key <KEY>  <CONTRACT_ADDRESS_TO_VERIFY> <path>:<contractname>
   ```

   - Verify that the upgraded contracts are functioning as expected.
   - Perform any additional tests to ensure the stability and correctness of the deployment.
