// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";

contract BridgeTokensScript is Script {

    function run(
        address _recipient,
        uint64 _destinationChainSelector,
        address _ccipRouterAddress,
        address _tokenToSendAddress,
        uint256 _amountToSend,
        address _linkTokenAddress
    )
        public
    {
        vm.startBroadcast();
        // Construct the ccip message
        Client.EVMTokenAmount[] memory _tokenAmounts = new Client.EVMTokenAmount[](1);
        _tokenAmounts[0] = Client.EVMTokenAmount({token: _tokenToSendAddress, amount: _amountToSend});
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_recipient),
            data: "",
            tokenAmounts: _tokenAmounts,
            feeToken: _linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        // Calculate fees in link required for the message constructed
        uint256 ccipFee = IRouterClient(_ccipRouterAddress).getFee(_destinationChainSelector, ccipMessage);

        // Approve router to spend both link for fees and the tokens being send
        IERC20(_ccipRouterAddress).approve(_ccipRouterAddress, ccipFee);
        IERC20(_tokenToSendAddress).approve(_ccipRouterAddress, _amountToSend);
        // Send the message cross chain
        IRouterClient(_ccipRouterAddress).ccipSend(_destinationChainSelector, ccipMessage);
        vm.stopBroadcast();
    }

}
