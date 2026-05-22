// SPDX-License-Identifier: MIT

import {BurnMintRebaseTokenPool} from "../../src/BurnMintRebaseTokenPool.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/interfaces/IRebaseToken.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {Test, console} from "forge-std/Test.sol";

contract CrossChainTest is Test {

    // Addresses
    address owner = makeAddr("Owner");

    // Fork IDs
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

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
        ethSepoliaFork = vm.createSelectFork("eth_sepolia_rpc");
        arbSepoliaFork = vm.createFork("arbitrum_sepolia_rpc");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy and configure on Ethereum sepolia which is the current selected fork
        vm.startPrank(owner);
        // Deploy token on sepolia
        ethSepoliaToken = new RebaseToken();
        // Deploy Vault only on sepolia for users to deposit ETH for RBTs
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        // Deploy token pool. Uses Chainlink local to get gllobal chainlink values needed for pool deployment
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ethSepoliaPool = new BurnMintRebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            new address[](0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );
        // Claim burn and mint role to the pool. i.e., call token as owner and grant the burn and mint role to the
        // pool and vault
        ethSepoliaToken.grantMintAndBurnRole(address(vault));
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaPool));
        // Claim and accept admin role
        // Claim admin role. i.e., register the owner EOA as the admin for the deployed token on sepolia
        // Uses chainlink local for tokenAdminRegistry and RegistryModuleOwnerCustom contract addresses.
        RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(ethSepoliaToken));
        // Acept the admin role
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethSepoliaToken));

        // Link token to the pool
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(ethSepoliaToken), address(ethSepoliaPool));

        vm.stopPrank();

        // Deploy and configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        // Deploy token on Arbitrum sepolia
        arbSepoliaToken = new RebaseToken();
        // Deploy token pool. Uses Chainlink local to get gllobal chainlink values needed for pool deployment
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaPool = new BurnMintRebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        // Claim burn and mint role to the pool. i.e., call token as owner and grant the burn and mint role to the
        // pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        // Claim and accept admin role
        // Claim admin role. i.e., register the owner EOA as the admin for the deployed token on Arbitrum
        // Uses chainlink local for tokenAdminRegistry and RegistryModuleOwnerCustom contract addresses.
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        // Accept the admin role
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));

        // Link token to the pool
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();
    }

}
