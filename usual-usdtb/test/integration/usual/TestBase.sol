// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test, console2 } from "../../../lib/forge-std/src/Test.sol";
import {
    TransparentUpgradeableProxy
} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IUsualUSDTB } from "../../../src/usual/interfaces/IUsualUSDTB.sol";
import { IRegistryAccess } from "../../../src/usual/interfaces/IRegistryAccess.sol";
import { IUSDTB } from "../../../src/usual/interfaces/IUsdtb.sol";
import { UsualUSDTB } from "../../../src/usual/UsualUSDTB.sol";

import { USUAL_USDTB_UNWRAP, USUAL_USDTB_PAUSE, USUAL_USDTB_UNPAUSE, USUAL_USDTB_MINTCAP_ALLOCATOR } from "../../../src/constants.sol";

contract TestBase is Test {
    IUSDTB internal constant _usdtb = IUSDTB(0xC139190F447e929f090Edeb554D95AbB8b18aC1C);

    // Large USDTB holder on Ethereum Mainnet
    address internal constant _usdtbSource = 0x2B5AB59163a6e93b4486f6055D33CA4a115Dd4D5;

    IRegistryAccess internal constant _registryAccess = IRegistryAccess(0x0D374775E962c3608B8F0A4b8B10567DF739bb56);
    address internal _admin = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;

    address internal _treasury = makeAddr("treasury");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");

    uint256 internal _aliceKey = _makeKey("alice");

    address[] internal _accounts = [_alice, _bob, _carol];

    address internal _usualUSDTBImplementation;
    IUsualUSDTB internal _usualUSDTB;

    function _giveUSDTB(address account_, uint256 amount_) internal {
        vm.prank(_usdtbSource);
        _usdtb.transfer(account_, amount_);
    }

    function _giveEth(address account_, uint256 amount_) internal {
        vm.deal(account_, amount_);
    }

    function _wrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _usdtb.approve(address(_usualUSDTB), amount_);

        vm.prank(account_);
        _usualUSDTB.wrap(recipient_, amount_);
    }

    function _wrapWithPermitVRS(
        address account_,
        uint256 signerPrivateKey_,
        address recipient_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getPermit(account_, signerPrivateKey_, amount_, nonce_, deadline_);

        vm.prank(account_);
        _usualUSDTB.wrapWithPermit(recipient_, amount_, deadline_, v_, r_, s_);
    }

    function _unwrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _usualUSDTB.unwrap(recipient_, amount_);
    }

    function _deployComponents() internal {
        _usualUSDTBImplementation = address(new UsualUSDTB());
        bytes memory usualUSDTBData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(_usdtb),
            _registryAccess
        );
        _usualUSDTB = IUsualUSDTB(address(new TransparentUpgradeableProxy(_usualUSDTBImplementation, _admin, usualUSDTBData)));
    }

    function _fundAccounts() internal {
        for (uint256 i = 0; i < _accounts.length; ++i) {
            _giveUSDTB(_accounts[i], 10e18);
            _giveEth(_accounts[i], 0.1 ether);
        }
    }

    function _grantRoles() internal {
        vm.prank(_admin);
        IRegistryAccess(_registryAccess).grantRole(USUAL_USDTB_PAUSE, _admin);
        vm.prank(_admin);
        IRegistryAccess(_registryAccess).grantRole(USUAL_USDTB_UNPAUSE, _admin);

        for (uint256 i = 0; i < _accounts.length; ++i) {
            vm.prank(_admin);
            IRegistryAccess(_registryAccess).grantRole(USUAL_USDTB_UNWRAP, _accounts[i]);
        }

        vm.prank(_admin);
        IRegistryAccess(_registryAccess).grantRole(USUAL_USDTB_MINTCAP_ALLOCATOR, _admin);
    }

    /* ============ utils ============ */

    function _makeKey(string memory name_) internal returns (uint256 key_) {
        (, key_) = makeAddrAndKey(name_);
    }

    function _getPermit(
        address account_,
        uint256 signerPrivateKey_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_
    ) internal view returns (uint8 v_, bytes32 r_, bytes32 s_) {
        bytes32 PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
        return
            vm.sign(
                signerPrivateKey_,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        _usdtb.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                PERMIT_TYPEHASH,
                                account_,
                                address(_usualUSDTB),
                                amount_,
                                nonce_,
                                deadline_
                            )
                        )
                    )
                )
            );
    }
}
