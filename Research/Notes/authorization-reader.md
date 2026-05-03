# Authorization Reader
*May 2026*

`EmtunAuthorizationReader` composes `PolicyRootChain` and `EmtunVerifierAdapter` into the first end-to-end contract-facing SAP check. The reader resolves the current policy root for an agent identifier, verifies the inclusion proof against that root and the claimed `action_hash`, and returns `false` for stale roots, unopened chains, malformed proofs, or verifier failures. It does not register agents, assign marketplace tasks, or add execution semantics; its only job is to answer whether a proof authorizes one action under the current chain head.
