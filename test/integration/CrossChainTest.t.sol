// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BurnMintRebaseTokenPool} from "../../src/BurnMintRebaseTokenPool.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/interfaces/IRebaseToken.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {Test, console} from "forge-std/Test.sol";

contract CrossChainTest is Test {

    // Addresses
    address owner = makeAddr("Owner");
    address crossChainUser = makeAddr("cross chain sender");

    // Fork IDs
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    uint256 SEND_AMOUNT = 1e5;

    // Chainlink local instance
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    // Tokens on both chains
    RebaseToken ethSepoliaToken;
    RebaseToken arbSepoliaToken;

    // Vault contract only on source chain which is eth sepolia
    Vault vault;

    // Token pools on both chains
    BurnMintRebaseTokenPool ethSepoliaPool;
    BurnMintRebaseTokenPool arbSepoliaPool;

    // Network details
    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(crossChainUser, "crossChainUser");
        ethSepoliaFork = vm.createSelectFork("eth_sepolia_rpc");
        arbSepoliaFork = vm.createFork("arbitrum_sepolia_rpc");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy and configure on Ethereum Sepolia
        vm.startPrank(owner);
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ethSepoliaPool = new BurnMintRebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            new address[](0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );

        // Grant burn/mint permissions to vault and pool
        ethSepoliaToken.grantMintAndBurnRole(address(vault));
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaPool));

        // Register token admin and accept admin role via Chainlink's token admin registry
        RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(ethSepoliaToken));
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethSepoliaToken));

        // Link token to its pool for cross-chain transfers
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(ethSepoliaToken), address(ethSepoliaPool));
        vm.stopPrank();

        // Deploy and configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        // Deploy token on Arbitrum sepolia
        arbSepoliaToken = new RebaseToken();
        // Deploy token pool. Uses Chainlink local to get global chainlink values needed for pool deployment
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        arbSepoliaPool = new BurnMintRebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Grant burn/mint permissions to pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        // Register token admin and accept admin role via Chainlink's token admin registry
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));

        // Link token to its pool for cross-chain transfers
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();

        // Configure each pool with its remote chain counterpart
        configureTokenPool(
            ethSepoliaFork,
            address(ethSepoliaPool),
            address(arbSepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            address(ethSepoliaPool),
            ethSepoliaNetworkDetails.chainSelector,
            address(ethSepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 _forkId,
        address _localPool,
        address _remotePool,
        uint64 _remoteChainSelector,
        address _remoteTokenAddress
    )
        public
    {
        vm.selectFork(_forkId);
        vm.startPrank(owner);
        bytes[] memory _remotePoolAddresses = new bytes[](1);
        /// @dev The local simulator fork encodes pool addresses using `abi.encodePacked`.
        /// Using `abi.encode` here would cause remote/source pool validation to fail.
        ///
        /// In `TokenPool`, chain configuration updates store the `keccak256` hash of the
        /// pool address bytes rather than the raw address itself. During validation on
        /// the destination chain, the provided source pool address is hashed and compared
        /// against the previously stored hash.
        ///
        /// Ideally, addresses should be encoded with `abi.encode` before hashing.
        /// However, to remain compatible with the current Chainlink CCIP implementation,
        /// which passes source pool addresses encoded with `abi.encodePacked`, this test
        /// also uses `abi.encodePacked`.

        _remotePoolAddresses[0] = abi.encodePacked(_remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            remotePoolAddresses: _remotePoolAddresses,
            remoteTokenAddress: abi.encode(_remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(_localPool).applyChainUpdates(new uint64[](0), chainsToAdd);

        vm.stopPrank();
    }

    /// Helper function to send tokens across chains (Sepolia ↔ Arbitrum Sepolia)
    function bridgeTokens(
        uint256 _amountToBridge,
        uint256 _localFork,
        uint256 _remoteFork,
        Register.NetworkDetails memory _localNetworkDetails,
        Register.NetworkDetails memory _remoteNetworkDetails,
        RebaseToken _localToken,
        RebaseToken _remoteToken
    )
        public
    {
        vm.selectFork(_localFork);

        // Prepare token amounts to transfer
        Client.EVMTokenAmount[] memory __tokenAmounts = new Client.EVMTokenAmount[](1);
        __tokenAmounts[0] = Client.EVMTokenAmount({token: address(_localToken), amount: _amountToBridge});

        // Construct CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(crossChainUser),
            data: "",
            tokenAmounts: __tokenAmounts,
            feeToken: _localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000}))
        });

        // Calculate and fund fees to the user address.
        uint256 fee =
            IRouterClient(_localNetworkDetails.routerAddress).getFee(_remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(crossChainUser, fee);

        // Approve router to spend LINK for fees
        vm.prank(crossChainUser);
        IERC20(_localNetworkDetails.linkAddress).approve(_localNetworkDetails.routerAddress, fee);

        // Approve router to burn RBT tokens on source chain
        vm.prank(crossChainUser);
        IERC20(address(_localToken)).approve(_localNetworkDetails.routerAddress, _amountToBridge);

        // Verify token balance before transfer
        uint256 localBalBefore = _localToken.balanceOf(crossChainUser);

        // Send message across chains
        vm.prank(crossChainUser);
        IRouterClient(_localNetworkDetails.routerAddress).ccipSend(_remoteNetworkDetails.chainSelector, message);

        // Verify tokens burned on source chain
        uint256 localBalAfter = _localToken.balanceOf(crossChainUser);
        assertEq(localBalAfter, localBalBefore - _amountToBridge);

        // Cache source chain interest rate for verification on destination chain
        uint256 localChainUserInterestRate = _localToken.getUserInterestRate(crossChainUser);

        // Advance time and check destination chain balance before message receipt
        vm.selectFork(_remoteFork);
        vm.warp(block.timestamp + 30 minutes);
        uint256 remoteBalBefore = _remoteToken.balanceOf(crossChainUser);

        // Route message to destination chain
        vm.selectFork(_localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(_remoteFork);

        // Verify tokens minted on destination chain
        uint256 remoteBalAfter = _remoteToken.balanceOf(crossChainUser);
        assertEq(remoteBalAfter, remoteBalBefore + _amountToBridge);

        // Verify interest rate preserved across chains as the user didn't have tokens on destination chain.
        assertEq(_remoteToken.getUserInterestRate(crossChainUser), localChainUserInterestRate);
    }

    function testBridgeAllTokensFromSepoliaToArbitrumSepolia() public {
        vm.selectFork(ethSepoliaFork);

        // Mint rebase tokens: deposit ETH via vault
        vm.deal(crossChainUser, SEND_AMOUNT);
        vm.prank(crossChainUser);
        vault.deposit{value: SEND_AMOUNT}();

        // Verify user received RBTs equal to ETH deposited
        assertEq(ethSepoliaToken.balanceOf(crossChainUser), SEND_AMOUNT);

        // Bridge all tokens to Arbitrum Sepolia
        bridgeTokens(
            SEND_AMOUNT,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            ethSepoliaToken,
            arbSepoliaToken
        );
    }

}
