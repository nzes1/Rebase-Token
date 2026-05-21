// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BurnMintRebaseTokenPool is TokenPool {

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
        // tokens can be minted on the destination chain. first decode recipient address from the struct. But if we pass
        // recipient then a bug will exist when we are the ones sending tokens cross chain in that on dest chain, we
        // probably end up to have a
        // higher interest  rate if we have no tokens there. So the interest rate to pass should be of that of the
        // sender. the sender we can esily get from the struct originalSender variable. No need to abi decode

        //get interest rate from the rebasing token which is passed as an IERC20 at deployment and saved into i_token
        uint256 recipientInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        // then burn the tokens the user approved ccip to transfer from their account to the pool via the router.
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
        // Finally, we need to encode the interest rate into the lockOrBurnOutV1 struct so that it can be passed to the
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
        // different froim chainlllinks itself of tokenpool where they have this localAmount calculation thing.
        // uint256 localAmount = _calculateLocalAmount(
        //     releaseOrMintIn.sourceDenominatedAmount, _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        // );
        // validate release or mint and just pass the sourceDenominatedAmount directly
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);

        // now get recipient interest rate. From our rebase token desing, interest rate of recipient is set as that of
        // of whoever is sending - this case the originall sender rate as passed on destPoolData variablle of the
        // lockOrBurnOutV1 struct
        uint256 recipientInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        // Now we can call rebase token and mint the tokens
        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, recipientInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }

}

