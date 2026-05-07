# Task Funding Escrow
*May 2026*

`TaskFundingEscrow` lets a requester attach ETH to an open `TaskIntentMarket` task intent, then recover those funds only if the task intent is cancelled before assignment. The contract deliberately has no agent payout path, no result acceptance path, and no execution-settlement logic. This keeps the escrow boundary narrow: Emtun can model task funding without claiming that V1 verifies whether offchain work was completed correctly.
