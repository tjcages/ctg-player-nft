// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {IERC721AUpgradeable} from "erc721a-upgradeable/IERC721AUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CTGPlayerNFT} from "../src/CTGPlayerNFT.sol";
import {DummyMetadataRenderer} from "./utils/DummyMetadataRenderer.sol";
import {MockUser} from "./utils/MockUser.sol";
import {IMetadataRenderer} from "../src/interfaces/IMetadataRenderer.sol";
import {ICTGPlayerNFT} from "../src/interfaces/ICTGPlayerNFT.sol";
import {CTGPlayerNFTProxy} from "../src/CTGPlayerNFTProxy.sol";

contract CTGPlayerNFTTest is Test {
    /// @notice Event emitted when the funds are withdrawn from the minting contract
    /// @param withdrawnBy address that issued the withdraw
    /// @param withdrawnTo address that the funds were withdrawn to
    /// @param amount amount that was withdrawn
    /// @param feeRecipient user getting withdraw fee (if any)
    /// @param feeAmount amount of the fee getting sent (if any)
    event FundsWithdrawn(address indexed withdrawnBy, address indexed withdrawnTo, uint256 amount, address feeRecipient, uint256 feeAmount);

    event Sale(address indexed to, uint256 indexed purchaseQuantity, uint256 indexed pricePerToken, uint256 firstPurchasedTokenId);

    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 purchaseQuantity, string comment);

    address internal creator;
    address internal collector;
    address internal mintReferral;
    address internal createReferral;
    address internal zora;

    CTGPlayerNFT zoraNFTBase;
    MockUser mockUser;
    DummyMetadataRenderer public dummyRenderer = new DummyMetadataRenderer();
    address public constant DEFAULT_OWNER_ADDRESS = address(0x23499);
    address payable public constant DEFAULT_FUNDS_RECIPIENT_ADDRESS = payable(address(0x21303));
    address payable public constant DEFAULT_ZORA_DAO_ADDRESS = payable(address(0x999));
    address public constant UPGRADE_GATE_ADMIN_ADDRESS = address(0x942924224);
    address public constant mediaContract = address(0x123456);
    address public impl;

    struct Configuration {
        IMetadataRenderer metadataRenderer;
        uint64 editionSize;
        uint16 royaltyBPS;
        address payable fundsRecipient;
    }

    modifier setupZoraNFTBase(uint64 editionSize) {
        bytes[] memory setupCalls = new bytes[](0);
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: editionSize,
            _royaltyRecipient: DEFAULT_OWNER_ADDRESS,
            _royaltyBPS: 800,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });

        _;
    }

    modifier setupZoraNFTBaseWithCreateReferral(uint64 editionSize, address initCreateReferral) {
        bytes[] memory setupCalls = new bytes[](0);
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: editionSize,
            _royaltyRecipient: DEFAULT_OWNER_ADDRESS,
            _royaltyBPS: 800,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });

        _;
    }

    function setUp() public {
        creator = makeAddr("creator");
        collector = makeAddr("collector");
        mintReferral = makeAddr("mintReferral");
        createReferral = makeAddr("createReferral");
        zora = makeAddr("zora");

        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        impl = address(new CTGPlayerNFT());
        address payable newDrop = payable(address(new CTGPlayerNFTProxy(impl, "")));
        zoraNFTBase = CTGPlayerNFT(newDrop);
    }

    modifier withFactory() {
        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        impl = address(new CTGPlayerNFT());
        address payable newDrop = payable(address(new CTGPlayerNFTProxy(impl, "")));
        zoraNFTBase = CTGPlayerNFT(newDrop);

        _;
    }

    function test_Init() public setupZoraNFTBase(10) {
        require(zoraNFTBase.owner() == DEFAULT_OWNER_ADDRESS, "Default owner set wrong");

        (IMetadataRenderer renderer, uint64 editionSize, uint16 royaltyBPS, address payable fundsRecipient) = zoraNFTBase.config();

        require(address(renderer) == address(dummyRenderer));
        require(editionSize == 10, "EditionSize is wrong");
        require(royaltyBPS == 800, "RoyaltyBPS is wrong");
        require(fundsRecipient == payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS), "FundsRecipient is wrong");

        string memory name = zoraNFTBase.name();
        string memory symbol = zoraNFTBase.symbol();
        require(keccak256(bytes(name)) == keccak256(bytes("Test NFT")));
        require(keccak256(bytes(symbol)) == keccak256(bytes("TNFT")));

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        bytes[] memory setupCalls = new bytes[](0);
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: 10,
            _royaltyRecipient: DEFAULT_OWNER_ADDRESS,
            _royaltyBPS: 800,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });
    }

    function test_InitFailsTooHighRoyalty() public {
        bytes[] memory setupCalls = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(ICTGPlayerNFT.Setup_RoyaltyPercentageTooHigh.selector, 5000));
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: 10,
            // 80% royalty is above 50% max.
            _royaltyRecipient: DEFAULT_OWNER_ADDRESS,
            _royaltyBPS: 8000,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });
    }

    function test_RoyaltyUpdates() public setupZoraNFTBase(1) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.updateRoyaltySettings(address(0x443), 1200); // 12%
        (address recipient, uint256 amount) = zoraNFTBase.royaltyInfo(1, 1 ether);
        assertEq(amount, 0.12 ether);
        assertEq(recipient, address(0x443));
    }

    function test_IsAdminGetter() public setupZoraNFTBase(1) {
        assertTrue(zoraNFTBase.isAdmin(DEFAULT_OWNER_ADDRESS));
        assertTrue(!zoraNFTBase.isAdmin(address(0x999)));
        assertTrue(!zoraNFTBase.isAdmin(address(0)));
    }

    function test_RoyaltyInfo() public setupZoraNFTBase(10) {
        // assert 800 royaltyAmount or 8%
        (, uint256 royaltyAmount) = zoraNFTBase.royaltyInfo(10, 1 ether);
        assertEq(royaltyAmount, 0.08 ether);
    }

    function test_NoRoyaltyInfoNoFundsRecipientAddress() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setFundsRecipient(payable(address(0)));
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.updateRoyaltySettings(address(0), 1500);
        // assert 800 royaltyAmount or 8%
        (address royaltyRecipient, uint256 royaltyAmount) = zoraNFTBase.royaltyInfo(10, 1 ether);
        assertEq(royaltyAmount, 0 ether);
        assertEq(royaltyRecipient, address(0));
    }

    function test_PurchaseFreeMint(uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        (, uint256 protocolFee) = zoraNFTBase.zoraFeeForAmount(purchaseQuantity);
        uint256 paymentAmount = protocolFee;
        vm.deal(address(456), paymentAmount);
        vm.prank(address(456));
        vm.expectEmit(true, true, true, true);
        emit Sale(address(456), purchaseQuantity, 0, 0);
        zoraNFTBase.purchase{value: paymentAmount}(purchaseQuantity);

        assertEq(zoraNFTBase.saleDetails().maxSupply, purchaseQuantity);
        assertEq(zoraNFTBase.saleDetails().totalMinted, purchaseQuantity);
        require(zoraNFTBase.ownerOf(1) == address(456), "owner is wrong for new minted token");
        assertEq(address(zoraNFTBase).balance, paymentAmount - protocolFee);
    }

    function test_PurchaseWithValue(uint64 salePrice, uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(salePrice > 0);
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        (, uint256 zoraFee) = zoraNFTBase.zoraFeeForAmount(purchaseQuantity);
        uint256 paymentAmount = uint256(salePrice) * purchaseQuantity + zoraFee;
        vm.deal(address(456), paymentAmount);
        vm.prank(address(456));
        vm.expectEmit(true, true, true, true);
        emit Sale(address(456), purchaseQuantity, salePrice, 0);
        zoraNFTBase.purchase{value: paymentAmount}(purchaseQuantity);

        assertEq(zoraNFTBase.saleDetails().maxSupply, purchaseQuantity);
        assertEq(zoraNFTBase.saleDetails().totalMinted, purchaseQuantity);
        require(zoraNFTBase.ownerOf(1) == address(456), "owner is wrong for new minted token");

        assertEq(address(zoraNFTBase).balance, 0);
        assertEq(address(DEFAULT_FUNDS_RECIPIENT_ADDRESS).balance, uint256(salePrice) * uint256(purchaseQuantity));
    }

    function test_PurchaseWithValueWrongPrice() public setupZoraNFTBase(100) {
        uint256 purchaseQuantity = 2;
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 1 ether,
            maxSalePurchasePerAddress: 1000,
            presaleMerkleRoot: bytes32(0)
        });

        vm.deal(address(456), 1 ether);
        vm.prank(address(456));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent(uint256,uint256)", 1000000000000000000, 2000000000000000000));
        zoraNFTBase.purchase{value: 1 ether}(purchaseQuantity);

        assertEq(zoraNFTBase.saleDetails().maxSupply, 100);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 0);
        vm.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        zoraNFTBase.ownerOf(1);
    }

    function test_PurchaseWithComment(uint64 salePrice, uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        uint256 paymentAmount = uint256(salePrice) * purchaseQuantity;
        vm.deal(address(456), paymentAmount);
        vm.prank(address(456));
        vm.expectEmit(true, true, true, true);
        emit MintComment(address(456), address(zoraNFTBase), 0, purchaseQuantity, "test comment");
        zoraNFTBase.purchaseWithComment{value: paymentAmount}(purchaseQuantity, "test comment");
    }

    function test_PurchaseWithCommentLimitsPurchaseNumber() public setupZoraNFTBase(10) {
        uint104 salePrice = 0.01 ether;
        uint32 purchaseQuantity = 23;

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        vm.deal(collector, 10000 ether);
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("Mint_SoldOut()"));
        zoraNFTBase.purchaseWithComment{value: salePrice * 23}({quantity: 23, comment: "testing"});

        vm.prank(collector);
        zoraNFTBase.purchaseWithComment{value: salePrice * 10}({quantity: 10, comment: "testing"});

        assertEq(zoraNFTBase.balanceOf(collector), 10);
    }

    function test_PurchaseWithRecipient(uint64 salePrice, uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        uint256 paymentAmount = uint256(salePrice) * purchaseQuantity;

        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");

        vm.deal(minter, paymentAmount);
        vm.prank(minter);
        zoraNFTBase.purchaseWithRecipient{value: paymentAmount}(recipient, purchaseQuantity, "");

        for (uint256 i; i < purchaseQuantity; ) {
            assertEq(zoraNFTBase.ownerOf(++i), recipient);
        }
    }

    function test_PurchaseWithRecipientAndComment(uint64 salePrice, uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        (, uint256 zoraFee) = zoraNFTBase.zoraFeeForAmount(purchaseQuantity);
        uint256 paymentAmount = uint256(salePrice) * purchaseQuantity + zoraFee;

        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");

        vm.deal(minter, paymentAmount);

        vm.expectEmit(true, true, true, true);
        emit MintComment(minter, address(zoraNFTBase), 0, purchaseQuantity, "test comment");
        vm.prank(minter);
        zoraNFTBase.purchaseWithRecipient{value: paymentAmount}(recipient, purchaseQuantity, "test comment");
    }

    function testRevert_PurchaseWithInvalidRecipient(uint64 salePrice, uint32 purchaseQuantity) public setupZoraNFTBase(purchaseQuantity) {
        vm.assume(purchaseQuantity < 100 && purchaseQuantity > 0);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: salePrice,
            maxSalePurchasePerAddress: purchaseQuantity + 1,
            presaleMerkleRoot: bytes32(0)
        });

        (, uint256 zoraFee) = zoraNFTBase.zoraFeeForAmount(purchaseQuantity);
        uint256 paymentAmount = uint256(salePrice) * purchaseQuantity + zoraFee;

        address minter = makeAddr("minter");
        address recipient = address(0);

        vm.deal(minter, paymentAmount);

        vm.expectRevert(abi.encodeWithSignature("MintToZeroAddress()"));
        vm.prank(minter);
        zoraNFTBase.purchaseWithRecipient{value: paymentAmount}(recipient, purchaseQuantity, "");
    }

    function test_UpgradeApproved() public setupZoraNFTBase(10) {
        address newImpl = address(new CTGPlayerNFT());

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.UPGRADER_ROLE(), DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.upgradeToAndCall(newImpl, "");
    }

    function test_UpgradeFailsNotApproved() public setupZoraNFTBase(10) {
        address newImpl = address(new CTGPlayerNFT());

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        vm.expectRevert(ICTGPlayerNFT.NotAllowedToUpgrade.selector);
        zoraNFTBase.upgradeToAndCall(newImpl, "");
    }

    function test_PurchaseTime() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: 0,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });

        assertTrue(!zoraNFTBase.saleDetails().publicSaleActive);

        (, uint256 fee) = zoraNFTBase.zoraFeeForAmount(1);

        vm.deal(address(456), 1 ether);
        vm.prank(address(456));
        vm.expectRevert(ICTGPlayerNFT.Sale_Inactive.selector);
        zoraNFTBase.purchase{value: 0.1 ether + fee}(1);

        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 0);

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 9 * 3600,
            publicSaleEnd: 11 * 3600,
            presaleStart: 0,
            presaleEnd: 0,
            maxSalePurchasePerAddress: 20,
            publicSalePrice: 0.1 ether,
            presaleMerkleRoot: bytes32(0)
        });

        assertTrue(!zoraNFTBase.saleDetails().publicSaleActive);
        // jan 1st 1980
        vm.warp(10 * 3600);
        assertTrue(zoraNFTBase.saleDetails().publicSaleActive);
        assertTrue(!zoraNFTBase.saleDetails().presaleActive);

        vm.prank(address(456));
        zoraNFTBase.purchase{value: 0.1 ether + fee}(1);

        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        assertEq(zoraNFTBase.ownerOf(1), address(456));
    }

    function test_Mint() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        require(zoraNFTBase.ownerOf(1) == DEFAULT_OWNER_ADDRESS, "Owner is wrong for new minted token");
    }

    function test_MulticallAccessControl() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0,
            maxSalePurchasePerAddress: 10,
            presaleMerkleRoot: bytes32(0)
        });

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, address(0x456), 1);
        calls[1] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, address(0x123), 3);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICTGPlayerNFT.Access_MissingRoleOrAdmin.selector,
                bytes32(0xf0887ba65ee2024ea881d91b74c2450ef19e1557f03bed3ea9f16b037cbe2dc9)
            )
        );
        zoraNFTBase.multicall(calls);

        assertEq(zoraNFTBase.balanceOf(address(0x123)), 0);

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.multicall(calls);

        assertEq(zoraNFTBase.balanceOf(address(0x123)), 3);
        assertEq(zoraNFTBase.balanceOf(address(0x456)), 1);
    }

    function test_MintMulticall() public setupZoraNFTBase(10) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, DEFAULT_OWNER_ADDRESS, 5);
        calls[1] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, address(0x123), 3);
        calls[2] = abi.encodeWithSelector(ICTGPlayerNFT.saleDetails.selector);
        bytes[] memory results = zoraNFTBase.multicall(calls);

        (bool saleActive, bool presaleActive, uint256 publicSalePrice, , , , , , , , ) = abi.decode(
            results[2],
            (bool, bool, uint256, uint64, uint64, uint64, uint64, bytes32, uint256, uint256, uint256)
        );
        assertTrue(!saleActive);
        assertTrue(!presaleActive);
        assertEq(publicSalePrice, 0);
        uint256 firstMintedId = abi.decode(results[0], (uint256));
        uint256 secondMintedId = abi.decode(results[1], (uint256));
        assertEq(firstMintedId, 5);
        assertEq(secondMintedId, 8);
    }

    function test_UpdatePriceMulticall() public setupZoraNFTBase(10) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(ICTGPlayerNFT.setSaleConfiguration.selector, 0.1 ether, 2, 0, type(uint64).max, 0, 0, bytes32(0));
        calls[1] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, address(0x123), 3);
        calls[2] = abi.encodeWithSelector(ICTGPlayerNFT.adminMint.selector, address(0x123), 3);
        bytes[] memory results = zoraNFTBase.multicall(calls);

        ICTGPlayerNFT.SaleDetails memory saleDetails = zoraNFTBase.saleDetails();

        assertTrue(saleDetails.publicSaleActive);
        assertTrue(!saleDetails.presaleActive);
        assertEq(saleDetails.publicSalePrice, 0.1 ether);
        uint256 firstMintedId = abi.decode(results[1], (uint256));
        uint256 secondMintedId = abi.decode(results[2], (uint256));
        assertEq(firstMintedId, 3);
        assertEq(secondMintedId, 6);
        vm.stopPrank();
        vm.startPrank(address(0x111));
        vm.deal(address(0x111), 0.3 ether);
        zoraNFTBase.purchase{value: 0.2 ether}(2);
        assertEq(zoraNFTBase.balanceOf(address(0x111)), 2);
        vm.stopPrank();
    }

    function test_MintWrongValue() public setupZoraNFTBase(10) {
        vm.deal(address(456), 1 ether);
        vm.prank(address(456));
        vm.expectRevert(ICTGPlayerNFT.Sale_Inactive.selector);
        zoraNFTBase.purchase{value: 0.12 ether}(1);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.15 ether,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });
        vm.prank(address(456));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent(uint256,uint256)", 120000000000000000, 150000000000000000));
        zoraNFTBase.purchase{value: 0.12 ether}(1);
    }

    function test_Withdraw(uint128 amount) public setupZoraNFTBase(10) {
        vm.assume(amount > 0.01 ether);
        vm.deal(address(zoraNFTBase), amount);
        uint256 leftoverFunds = amount;

        vm.prank(DEFAULT_OWNER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit FundsWithdrawn(DEFAULT_OWNER_ADDRESS, DEFAULT_FUNDS_RECIPIENT_ADDRESS, leftoverFunds, payable(address(0)), 0);
        zoraNFTBase.withdraw();

        assertEq(DEFAULT_FUNDS_RECIPIENT_ADDRESS.balance, amount);
    }

    function test_WithdrawNoZoraFee(uint128 amount) public setupZoraNFTBase(10) {
        vm.assume(amount > 0.01 ether);

        address payable fundsRecipientTarget = payable(address(0x0325));

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setFundsRecipient(fundsRecipientTarget);

        vm.deal(address(zoraNFTBase), amount);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit FundsWithdrawn(DEFAULT_OWNER_ADDRESS, fundsRecipientTarget, amount, payable(address(0)), 0);
        zoraNFTBase.withdraw();

        assertTrue(fundsRecipientTarget.balance == uint256(amount));
    }

    function test_MintLimit(uint8 limit) public setupZoraNFTBase(5000) {
        // set limit to speed up tests
        vm.assume(limit > 0 && limit < 50);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: limit,
            presaleMerkleRoot: bytes32(0)
        });
        (, uint256 limitFee) = zoraNFTBase.zoraFeeForAmount(limit);
        vm.deal(address(456), 100_000_000 ether);
        vm.prank(address(456));
        zoraNFTBase.purchase{value: 0.1 ether * uint256(limit) + limitFee}(limit);

        assertEq(zoraNFTBase.saleDetails().totalMinted, limit);

        (, uint256 fee) = zoraNFTBase.zoraFeeForAmount(1);
        vm.deal(address(444), 1_000_000 ether);
        vm.prank(address(444));
        vm.expectRevert(ICTGPlayerNFT.Purchase_TooManyForAddress.selector);
        zoraNFTBase.purchase{value: (0.1 ether * (uint256(limit) + 1)) + (fee * (uint256(limit) + 1))}(uint256(limit) + 1);

        assertEq(zoraNFTBase.saleDetails().totalMinted, limit);
    }

    function testSetSalesConfiguration() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 100,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 10,
            presaleMerkleRoot: bytes32(0)
        });

        (, , , , , uint64 presaleEndLookup, ) = zoraNFTBase.salesConfig();
        assertEq(presaleEndLookup, 100);

        address SALES_MANAGER_ADDR = address(0x11002);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.SALES_MANAGER_ROLE(), SALES_MANAGER_ADDR);
        vm.stopPrank();
        vm.prank(SALES_MANAGER_ADDR);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 100,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 1003,
            presaleMerkleRoot: bytes32(0)
        });

        (, , , , uint64 presaleStartLookup2, uint64 presaleEndLookup2, ) = zoraNFTBase.salesConfig();
        assertEq(presaleEndLookup2, 0);
        assertEq(presaleStartLookup2, 100);
    }

    function test_GlobalLimit(uint16 limit) public setupZoraNFTBase(uint64(limit)) {
        vm.assume(limit > 0);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, limit);
        vm.expectRevert(ICTGPlayerNFT.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
    }

    function test_WithdrawNotAllowed() public setupZoraNFTBase(10) {
        vm.expectRevert(ICTGPlayerNFT.Access_WithdrawNotAllowed.selector);
        zoraNFTBase.withdraw();
    }

    function test_InvalidFinalizeOpenEdition() public setupZoraNFTBase(5) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.2 ether,
            presaleMerkleRoot: bytes32(0),
            maxSalePurchasePerAddress: 5
        });
        (, uint256 fee) = zoraNFTBase.zoraFeeForAmount(3);
        zoraNFTBase.purchase{value: 0.6 ether + fee}(3);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        vm.expectRevert(ICTGPlayerNFT.Admin_UnableToFinalizeNotOpenEdition.selector);
        zoraNFTBase.finalizeOpenEdition();
    }

    function test_ValidFinalizeOpenEdition() public setupZoraNFTBase(type(uint64).max) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.2 ether,
            presaleMerkleRoot: bytes32(0),
            maxSalePurchasePerAddress: 10
        });
        (, uint256 fee) = zoraNFTBase.zoraFeeForAmount(3);
        zoraNFTBase.purchase{value: 0.6 ether + fee}(3);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.finalizeOpenEdition();
        vm.expectRevert(ICTGPlayerNFT.Mint_SoldOut.selector);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.expectRevert(ICTGPlayerNFT.Mint_SoldOut.selector);
        zoraNFTBase.purchase{value: 0.6 ether}(3);
    }

    function test_AdminMint() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        require(zoraNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS) == 1, "Wrong balance");
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.prank(minter);
        zoraNFTBase.adminMint(minter, 1);
        require(zoraNFTBase.balanceOf(minter) == 1, "Wrong balance");
        assertEq(zoraNFTBase.saleDetails().totalMinted, 2);
    }

    function test_EditionSizeZero() public setupZoraNFTBase(0) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        vm.expectRevert(ICTGPlayerNFT.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectRevert(ICTGPlayerNFT.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(minter, 1);

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 1,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });

        vm.deal(address(456), uint256(1) * 2);
        vm.prank(address(456));
        vm.expectRevert(abi.encodeWithSignature("Mint_SoldOut()"));
        zoraNFTBase.purchase{value: 1}(1);
    }

    // test Admin airdrop
    function test_AdminMintAirdrop() public setupZoraNFTBase(1000) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        address[] memory toMint = new address[](4);
        toMint[0] = address(0x10);
        toMint[1] = address(0x11);
        toMint[2] = address(0x12);
        toMint[3] = address(0x13);
        zoraNFTBase.adminMintAirdrop(toMint);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 4);
        assertEq(zoraNFTBase.balanceOf(address(0x10)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x11)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x12)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x13)), 1);
    }

    function test_AdminMintAirdropFails() public setupZoraNFTBase(1000) {
        vm.startPrank(address(0x10));
        address[] memory toMint = new address[](4);
        toMint[0] = address(0x10);
        toMint[1] = address(0x11);
        toMint[2] = address(0x12);
        toMint[3] = address(0x13);
        bytes32 minterRole = zoraNFTBase.MINTER_ROLE();
        vm.expectRevert(abi.encodeWithSignature("Access_MissingRoleOrAdmin(bytes32)", minterRole));
        zoraNFTBase.adminMintAirdrop(toMint);
    }

    // test admin mint non-admin permissions
    function test_AdminMintBatch() public setupZoraNFTBase(1000) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 100);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 100);
        assertEq(zoraNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS), 100);
    }

    function test_AdminMintBatchFails() public setupZoraNFTBase(1000) {
        vm.startPrank(address(0x10));
        bytes32 role = zoraNFTBase.MINTER_ROLE();
        vm.expectRevert(abi.encodeWithSignature("Access_MissingRoleOrAdmin(bytes32)", role));
        zoraNFTBase.adminMint(address(0x10), 100);
    }

    function test_Burn() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.startPrank(minter);
        address[] memory airdrop = new address[](1);
        airdrop[0] = minter;
        zoraNFTBase.adminMintAirdrop(airdrop);
        zoraNFTBase.burn(1);
        vm.stopPrank();
    }

    function test_BurnNonOwner() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.startPrank(minter);
        address[] memory airdrop = new address[](1);
        airdrop[0] = minter;
        zoraNFTBase.adminMintAirdrop(airdrop);
        vm.stopPrank();

        vm.prank(address(1));
        vm.expectRevert(IERC721AUpgradeable.TransferCallerNotOwnerNorApproved.selector);
        zoraNFTBase.burn(1);
    }

    function test_AdminMetadataRendererUpdateCall() public setupZoraNFTBase(10) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        assertEq(dummyRenderer.someState(), "");
        zoraNFTBase.callMetadataRenderer(abi.encodeWithSelector(DummyMetadataRenderer.updateSomeState.selector, "new state", address(zoraNFTBase)));
        assertEq(dummyRenderer.someState(), "new state");
    }

    function test_NonAdminMetadataRendererUpdateCall() public setupZoraNFTBase(10) {
        vm.startPrank(address(0x99493));
        assertEq(dummyRenderer.someState(), "");
        bytes memory targetCall = abi.encodeWithSelector(DummyMetadataRenderer.updateSomeState.selector, "new state", address(zoraNFTBase));
        vm.expectRevert(ICTGPlayerNFT.Access_OnlyAdmin.selector);
        zoraNFTBase.callMetadataRenderer(targetCall);
        assertEq(dummyRenderer.someState(), "");
    }

    function test_EIP165() public view {
        require(zoraNFTBase.supportsInterface(0x01ffc9a7), "supports 165");
        require(zoraNFTBase.supportsInterface(0x80ac58cd), "supports 721");
        require(zoraNFTBase.supportsInterface(0x5b5e139f), "supports 721-metdata");
        require(zoraNFTBase.supportsInterface(0x2a55205a), "supports 2981");
        require(zoraNFTBase.supportsInterface(0x49064906), "supports 4906");
        require(!zoraNFTBase.supportsInterface(0x0000000), "doesnt allow non-interface");
    }
}
