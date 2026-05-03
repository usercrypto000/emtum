# Policy Root Chain
*May 2026*

`PolicyRootChain` models the production chain-head rule without turning into the full `AgentRegistry`. Each agent identifier has one controller, one current root, and historical root records with monotonic versions. Older roots remain queryable for auditability, but `isCurrentRoot` only accepts the active chain head, which preserves the "no version window" security constraint from the production architecture.
