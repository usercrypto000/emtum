# Task Settlement Stateful Fuzz
*May 2026*

`TaskSettlementStatefulFuzz` models the full marketplace settlement path across randomized operation sequences: open, fund, claim, commit, accept, release, cancel, and refund. The invariant is that released escrows always correspond to accepted result hashes, while contract balances match the model after every successful payment or refund. This extends confidence in the settlement surface without changing the V1 boundary that requester acceptance is not execution verification.
