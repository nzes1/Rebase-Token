// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract RebaseTokenPool is TokenPool {

    constructor(
        IERC20 _token,
        address[] memory _allowList,
        address _rmnProxy,
        address _router
    )
        TokenPool(_token, 18, _allowList, _rmnProxy, _router)
    {}

    // Override the lockOrBurn function to handle rebasing tokens
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // Begin by validating the lockOrBurnIn parameters using the existing validation logic in TokenPool
        _validateLockOrBurn(lockOrBurnIn);

        // We need to pass the recipients current interest rate to the destination chain so that the correct amount of
        // tokens can be minted on the destination chain. first decode recipient address from the struct
        address recipient = abi.decode(lockOrBurnIn.receiver, (address));
        //get interest rate from the rebasing token which is passed as an IERC20 at deployment and saved into i_token
        uint256 recipientInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(recipient);
        // then burn the tokens the user approved ccip to transfer from their account to the pool via the router.
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
        // Finally, we need to encode the interest rate into the lockOrBurnOut struct so that it can be passed to the
        // destination chain.
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(recipientInterestRate)
        });
    }

    // override the releaseOrMint function to handle rebasing tokens
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        virtual
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        // before validation - we need the local amount as per source
        // Calculate the local amount
        // But for our case where the token decimals are the same, doing the calculation as below will be wrong since
        // we ddi not pass decimals from source chain. the sourcepooldata below for us has user's interest rate and will
        // thus calculate the wrong thing.
        // We will thus just call validate internal function and instead of a calculated localAAMount, just pass the
        // sourceDenominatedAmount directly. I have left this comments here to explain why the implementation is
        // different froim chainlllinks itselllf of tokenpool where thet have this localAmount calculation thing.
        // uint256 localAmount = _calculateLocalAmount(
        //     releaseOrMintIn.sourceDenominatedAmount, _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        // );
        // validate release or mint and just pass the sourceDenominatedAmount directly
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);

        // now get recipient interest rate
        uint256 recipientInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        // Now we can call rebase token and mint the tokens
        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, recipientInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }

}
// get the address of the user initiating the cross-chain transfer.

// We then call getUserInterestRate(originalSender) on our rebase token contract (accessed via i_token, a state variable
// from TokenPool holding
