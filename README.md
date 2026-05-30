
## What

1. A protocol that allows users to deposit into a vault and in return they receive rebase tokens that represent their underlying balance,
2. Build a Rebase token for the protocol where the `balanceOf()` is dynamic to show changing balance of user's tokens with time.
   - This will be a rewards rebase token where balance increases linearly with time. 
   - Tokens to be minted to users only at an action by the user such as minting, burning, transfers, bridging etc
3. About the interest rate (the linear increase variable)
   - Should be individually set for each user based on some global interest rate that is set for the protocol, at the time the user deposits into the vault.
   - The global protocol interest rate can only decrease to incentivise/reward early adopters. This is meant to drive token adoption.
4. A featurte by design that both introduces a bug and works ass expected:
   1. suppos e I have 2 wallets. Do first deposit with my 1st wallet to the valult then get a higher interest rate
   2. Then later do a second deposit but using my second wallet, then due to global interest rate reducing over time, the second deposit will be mapped to a lower interest rate.
   3. This means If I transfer the RBTs from the first wallet where rate is higher to that second one, after transfer then my rate becomes the lower one for the whole tokens - due to how transfer is designed and only inherits the source rate when the recipient does not have any RBTs
   4. Howevr, the same way, if I transfer the tokens from 2nd wallet where rate is lowwer to the first one where rate is already high, the effective rate after transfer to wallet 1 become the  higher rate for all the tokens. This would mean I will be stealing from the protocol since depositing late I can still enjoy the early deposit rates as long as I entered the protocol early no matter how small deposit at start was.
   5. This is known not-issue. This is however not possible to effect the second persona. It is only the individual.
5. We have a lot of centralization due to use of only owner on most administrative controls
6. The interest rate if you look at how it changes with actions by user it is not really linear but rather compount interest. This is because the interest over time is calculated on any existing balance. so say I do a deposit, my initial interest say after 2 hours when I do a second depoist will be calculated based on only the initial deposit. But a second interest calculation say triggered by a deposit/transfer - then now that interest will not be calculated on the principal amount but rather the principal amount + any interest accrued last time updated. this means you can cheat the interest growth easily and earn so much interest which means it won't be linear but rather compounded. For demo project, this is acceptable. TODO: Research if I can close this gap.

### Some Notes
7. Cross chain messaging - ability to transfer arbitrary data across different chains
8. Bridging - a type of cross chain messaging that only transfers assets like tokens
9. 4 types of brodging exist:
   1.  Burn and mint bridging - burn the tokens on source chain and mint on destination chain.
   2.  Lock and unlock bridging - Lock in a vault on source and unlocked from vault on destination
   3.  Lock and Mint - Lock on source chain especially if it doesn't support minting new tokens or burning tokens and thus cannot mint the tokens later when they are bridged back to source. New Wrapped versions of the tokens are minted on the destination chain
   4.  Burn and Unlock - Burn on source and unlock on destination where the issuing chain will be the destination. Unlock on destination means the tokens are released from a vault on that chain.


# Bug on how remote token address is passed on  ChainUpdate struct
# Root Cause Analysis: Address Truncation Bug

## The Bug in configureTokenPool()

Looking at lines 161 and 166 of CrossChainTest.t.sol:

```solidity
_remotePoolAddresses[0] = abi.encode(_remotePool);  // Line 161
...
remoteTokenAddress: abi.encode(_remoteTokenAddress),  // Line 166
```

## The Problem

When you call `abi.encode(address)`, it pads the 20-byte address to 32 bytes.
Example: 0x6E1734aC57e76fcD7fD66266Ae0C2547dB3A713a becomes:
0x0000000000000000000000006e1734ac57e76fcd7fd66266ae0c2547db3a713a

This is stored as `bytes` in the TokenPool's remoteChainConfigs mapping.

## When getRemoteToken() is called

The pool retrieves this 32-byte encoded value and returns it as the destTokenAddress.
However, the EVM2AnyTokenTransfer struct expects a 20-byte address, not 32 bytes.

## How Message Encoding Goes Wrong

When the message is being encoded for cross-chain transmission by CCIPLocalSimulatorFork:
1. The destTokenAddress comes back as 32 bytes: 0x0000...006e1734ac57e76fcd7fd66266ae0c2547db3a713a
2. The message encoding tries to fit this into an address field (20 bytes)
3. Due to how the encoding is done, it gets truncated

The fix is to properly decode the bytes to address when setting it:

```solidity
// WRONG (current):
remoteTokenAddress: abi.encode(_remoteTokenAddress),

// CORRECT:
remoteTokenAddress: _remoteTokenAddress,  // Or decode from bytes properly
```

OR ensure that when getting the remote token, we decode it properly from bytes to address.