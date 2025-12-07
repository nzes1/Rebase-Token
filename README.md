
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