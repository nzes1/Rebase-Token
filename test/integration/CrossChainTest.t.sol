// SPDX-License-Identifier: MIT

import {BurnMintRebaseTokenPool} from "../../src/BurnMintRebaseTokenPool.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sollib/chainlink-local/src/ccip/Register.sol";
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
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getGlobalInterestRate(block.chainid);

        ethSepoliaPool = new BurnMintRebaseTokenPool(
            IER20(address(ethSepoliaToken)),
            new address[](0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();

        // Deploy and configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaPool = new RebaseToken(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();
    }

}
