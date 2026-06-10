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

    /**
     * @notice Handles token lock/burn for outbound cross-chain transfers.
     * @param lockOrBurnIn The lock/burn input parameters from CCIP.
     * @return lockOrBurnOut The token address and metadata to pass to the destination chain.
     * @dev Overrides TokenPool.lockOrBurn to preserve user interest rates across chains.
     *      The sender's interest rate is encoded in destPoolData so the recipient inherits
     *      the sender's rate on the destination chain, ensuring consistent reward tiers.
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        uint256 recipientInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(recipientInterestRate)
        });
    }

    /**
     * @notice Handles token release/mint for inbound cross-chain transfers.
     * @param releaseOrMintIn The release/mint input parameters from CCIP.
     * @return The destination amount minted to the recipient.
     * @dev Overrides TokenPool.releaseOrMint to handle rebase-specific state.
     *      Unlike standard TokenPool, we skip decimal conversion since sourcePoolData
     *      contains the sender's interest rate (not remote decimals). The recipient
     *      receives tokens with the sender's interest rate, inherited via the transfer.
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        virtual
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);

        uint256 recipientInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, recipientInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }

}

