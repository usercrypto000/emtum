# Contract Map
*May 2026*

Emtun's contract surface is intentionally layered so authorization can be reasoned about without importing marketplace assumptions. `AgentRegistry` owns agent existence and opens a `PolicyRootChain` for each registered `agentId`. `PolicyRootChain` owns policy evolution through a current chain head and historical root records. `EmtunEASAttestationBoundary` records identity attestations through `MockEAS`, but those attestations point to the registry and chain-head mechanism rather than a single root value.

The proof path is separate. `HonkVerifier` is generated from the Noir circuit, `EmtunVerifierAdapter` wraps that generated verifier behind the two public SAP inputs, and `EmtunAuthorizationReader` resolves the current root before asking the adapter whether `action_hash` is authorized. This separation preserves the main trust boundary: identity attestation proves that an agent exists, while a SAP proof proves that one claimed action belongs to the agent's current committed policy set.
