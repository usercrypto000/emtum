# Task Intent Market
*May 2026*

`TaskIntentMarket` is the first marketplace-adjacent surface in the simulation, but it deliberately stops at task intent assignment. A requester publishes an `action_hash` and opaque `taskDataHash`; an agent can claim the task only if the current `AgentRegistry` owner submits the claim and `TaskAuthorizationGate` accepts its SAP proof against the current policy root and active identity attestation. The contract does not escrow funds, verify execution, arbitrate output quality, or release payment, which keeps the simulation boundary aligned with Emtun V1: authorization is proven, execution remains out of scope.
