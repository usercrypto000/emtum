# Emtun Production Constraints — Architectural Decisions Log
*April 2026*

---

## 1. Leaf Schema (Action Type Hierarchy)

The current simulation uses a flat `(action_type, scope, expiry, agent_salt)` tuple where `action_type` is a plain string hash. This is a deliberate simplification. The production question is whether `action_type` should remain a flat identifier or become a hierarchical capability path.

A flat hash treats every capability as fully independent. An agent authorized for `trading_analysis::technical::crypto` has no implicit authorization for `trading_analysis::technical`. Each capability is a distinct leaf. This is simpler to reason about and the circuit stays clean, but it means capability sets grow large for agents with broad authorization scopes.

A hierarchical scheme allows partial path matching — proving authorization at a parent node covers all children. This requires a more complex inclusion proof, possibly a separate circuit for hierarchy traversal, and significantly more circuit engineering effort.

Decision for the simulation: flat hash, fully independent capabilities. Decision for production: needs explicit resolution before the `AgentRegistry` contract is finalized. Changing the leaf schema after deployment invalidates every existing policy commitment and requires all agents to re-register. There is no migration path. Get this right before mainnet.

If the production decision is hierarchical, the capability taxonomy needs to be designed and frozen before the circuit is written for production. The taxonomy is a social coordination problem as much as a technical one — other platforms integrating Emtun as infrastructure need to agree on the same capability identifiers for the authorization layer to be interoperable.

---

## 2. Policy Root Chain (Policy Evolution Without Re-attestation)

The simulation uses a single root commitment per agent stored in `AgentRegistry`. Updating the policy set means a new root commitment and a new EAS attestation. This is acceptable for a simulation where policy sets are static during a test run.

Production agents have dynamic authorization scopes. A model update, an operator key rotation, or a permission change from an upstream principal all require policy evolution. Re-issuing an EAS attestation on every policy change is a liveness bottleneck and an economic cost that compounds at scale.

The production `AgentRegistry` must implement a policy root chain from deployment. Each agent maintains a chain head — an onchain pointer to the current policy root. The chain head updates in a single transaction. Each new root includes a hash pointer to its predecessor and a monotonic version counter. The EAS attestation points to the chain head address, not a specific root value. The root value lives in the chain, queryable but not embedded in the attestation.

This separates policy evolution from identity reissuance entirely. The EAS attestation stays stable across policy updates. The marketplace contract resolves the current root by reading the chain head at verification time.

Do not implement a version window (accepting N roots back from current). A version window keeps compromised old roots valid for N blocks, which directly contradicts Emtun's core security property. Chain head only, always current.

---

## 3. Proof Generation Latency (Bid Competitiveness)

A depth-8 Barretenberg proof currently takes several seconds locally. In a competitive marketplace with multiple agents bidding on the same task simultaneously, proof generation time becomes a latency disadvantage. An agent that holds a cached proof submits its bid faster than one generating a proof per bid.

The production optimization is a pre-computed proof cache. Agents generate inclusion proofs for their most frequently claimed action types ahead of time and store them locally. A cached proof remains valid as long as the policy root has not changed. On policy root update, the cache for all affected action types is invalidated and proofs must be regenerated.

The circuit must be designed with caching in mind from the start. Specifically, the public inputs (`policy_root` and `action_hash`) must be fully determined at proof generation time with no dependency on task-specific data. The current circuit design already satisfies this — the proof is purely about the relationship between an action hash and a policy root, with no task UID or requester address in the public inputs. That separation is intentional and must be preserved in production.

---

## 4. Verifier Gas Cost (Onchain Verification Economics)

The Barretenberg verifier contract is expensive. A single inclusion proof verification costs significantly more gas than a standard ERC-20 transfer. In a low-frequency marketplace this is acceptable. In a high-frequency marketplace with hundreds of task assignments per hour, per-verification gas cost makes the economics unworkable.

The production solution is proof aggregation. Multiple inclusion proof verifications are batched into a single onchain proof using a recursive circuit that verifies N individual proofs and outputs one aggregate proof. The marketplace contract calls the aggregate verifier once per batch rather than the individual verifier once per task. This reduces per-task verification cost proportional to batch size.

Recursive proof aggregation in Noir using Barretenberg is technically feasible but non-trivial. It is not a simulation concern. It is a production engineering task that should be scoped as a distinct milestone after the single-proof circuit is validated and deployed on a testnet.

Before that milestone, run a gas estimate on the generated verifier contract as soon as the simulation circuit is finalized. That number sets the baseline and informs the aggregation batch size calculation for production.

---

## 5. Execution Verification (Out of Scope for Emtun V1)

The simulation treats task execution as a trusted black box. The agent executes off-chain, posts a signed result hash onchain, and escrow releases on signature verification. There is no cryptographic proof that the execution actually occurred correctly or that the output corresponds to the task parameters.

This is an explicit scope boundary, not an oversight. Emtun V1 solves the authorization problem — proving an agent is permitted to perform a specific action within a committed policy set. Execution verification is a distinct and significantly harder problem, closer to verifiable compute territory and currently an open research problem in the broader ZK space.

The reputation attestation layer provides a weak economic deterrent against bad execution (negative attestations reduce future bid competitiveness) but it is reactive, not preventive. A production system with high-value tasks needs a stronger execution guarantee.

Execution verification is explicitly deferred to a future version. Every research piece and public communication about Emtun must be precise about this boundary. Emtun proves authorization. Proving execution correctness requires a separate primitive that does not yet exist in a practical form for general AI agent compute.

---

## 6. Infrastructure Abstraction (Emtun Beyond the Marketplace)

The marketplace is the proof of concept. The infrastructure play is the `AgentRegistry` contract plus the ZK inclusion proof circuit as a deployable SDK that other agent platforms can integrate as an authorization primitive.

Any system where AI agents need to prove scoped authorization without full capability disclosure is a potential integrator. The circuit is general. The registry is general. The EAS attestation schema is general. The marketplace is one application built on top of a general authorization layer.

This positioning changes the production roadmap. V1 is the simulation. V2 is a testnet deployment of the marketplace. V3 is the authorization SDK extracted as a standalone package with integration documentation, targeting other agent infrastructure projects as the primary audience.

The research piece should make this abstraction explicit. Part one establishes the general construction. Part two validates it with the marketplace simulation. The infrastructure framing is what makes Emtun a contribution to the agent economy stack, not just another marketplace implementation.

---

*This document governs architectural decisions for Emtun across simulation and production phases. Any decision marked as unresolved must be resolved before the corresponding production milestone begins. Do not close these items without explicit documentation of the resolution and its rationale.*
