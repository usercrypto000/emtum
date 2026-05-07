# Task Settlement Release
*May 2026*

Escrow release now follows requester acceptance of a committed result hash. The settlement predicate is narrow: an assigned agent commits a nonzero result hash, the requester accepts that exact hash, then `TaskFundingEscrow` releases funds to the current owner of the assigned `agentId`. This does not prove execution correctness. It only turns requester acceptance into the payment trigger while preserving the V1 boundary that Emtun proves scoped authorization, not offchain computation.
