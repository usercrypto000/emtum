---


---
## Scoped Authorization Proofs (SAP): A ZK Primitive for Agent Policy Commitment

### Project Emtun | April 2026

---

## Executive Summary: The Authorization Trust Boundary

Current agent identity discourse conflates three distinct cryptographic requirements. Validating existence is a registration problem. Authentication confirms identity. Verifying a specific authorization scope within a hidden boundary remains the unresolved cryptographic gap. While ERC-8004 (August 2025) and EIP-712 handle the first two layers, no deployed system provides a mechanism for scoped authorization. Scoped Authorization Proofs (SAP) introduce a ZK primitive designed to prove permission without total policy disclosure.

### Architectural Guardrails

1. **Authorization vs. Execution:** This construction proves permission, not execution correctness. Verifying the accuracy of AI agent output requires verifiable compute primitives that are currently impractical for general workloads. We are drawing a hard line at the authorization boundary to maintain technical rigor.
    
2. **The Chain Head Pattern:** We explicitly reject the version window model. Accepting N prior roots to accommodate policy updates creates an onchain window for compromised permissions. Our design utilizes a policy root chain head where the EAS attestation points to a pointer address. Updating the head in a single transaction immediately invalidates all prior state.
    

---

## Part One: The Primitive

### 1. Structural Failures in Deployed Systems

Existing agent frameworks suffer from two primary disclosure risks that enable adversarial targeting.

- **Full Capability Disclosure:** ERC-8004 registries resolve to (agentURI) files containing complete skill sets and service endpoints. Any observer can map an agent’s entire authorization boundary without interacting with it. In competitive marketplaces, this visibility allows adversaries to infer active monetization strategies by correlating bids against public capability declarations.
    
- **Flat Boolean Authorization:** Systems integrating x402 payments often rely on binary allowlists. These checks lack scope gradation or expiry binding. The resulting coupling of public identity with binary gates creates a brittle security model where the entire policy is readable and the gate is a simple (yes/no) switch.
    

Adjacent research using DIDs and Verifiable Credentials (arxiv 2505.19301, May 2025) identifies the need for fine-grained control but fails at the implementation layer. VCs require verifiers to read credential contents, thereby disclosing the boundary at verification time. Similarly, the EU Web3 Passport model (May 2025) collapses identity liveness and authorization into a single Merkle root query, preventing the functional separation required for high-frequency agent operations.

### 2. The Merkle Commitment Construction

A policy set is defined as a Merkle tree where each leaf is a Poseidon2 hash of the permission metadata.

$$Leaf = Poseidon2(action\_type, scope, expiry, agent\_salt)$$

We utilize per-leaf salting to prevent intra-agent timing analysis. An observer watching proof submission latency might otherwise infer tree structure. Independent randomization ensures that structurally identical leaves produce unique hashes, masking the internal policy configuration from the prover.

The ZK inclusion proof verifies two specific constraints:

1. The action_hash is the correct Poseidon2 output of the private preimage.
    
2. The Merkle root derived from the action_hash and private path matches the committed policy_root.
    

### 3. Policy Evolution Logic

Static roots fail in dynamic environments where model updates and key rotations are frequent. The policy root chain head ensures that an agent’s EAS attestation remains stable while its authorization logic evolves. Each new root contains a hash pointer to its predecessor and a monotonic version counter. By resolving the current root at the chain head, the marketplace contract ensures real-time validity without forcing the agent to reissue identity credentials.

---

## Part Two: The Simulation

### 4. Implementation Stack (Project Emtun)

Project Emtun serves as an empirical validation of the SAP primitive.

|**Layer**|**Technology**|
|---|---|
|**Circuit**|Noir (nargo 1.0.0-beta.19)|
|**Backend**|Barretenberg|
|**Contracts**|Foundry / Anvil|
|**Runtime**|TypeScript / Node.js|
|**Registry**|ERC-8004 + EAS|

### 5. Circuit Design and Poseidon Alignment

The circuit fixes the tree depth at 8, supporting 256 policy leaves. We replaced (std::merkle) with a custom (compute_merkle_root) helper to ensure Poseidon2 is used at every level. Mixing hash functions across layers frequently breaks consistency between TypeScript and Noir. Our alignment tests confirmed hash consistency across three diverse leaf inputs before proceeding to contract integration.

### 6. Verification Gate Lifecycle

1. **Task Posting:** Requesters lock escrowed funds and publish the (action_type_hash) to the marketplace.
    
2. **Bid Submission:** Agents submit an ERC-8004 reference, an EAS UID for the chain head, and the ZK inclusion proof.
    
3. **Validation:** The contract resolves the current root from the chain head and verifies the inclusion proof via the Barretenberg verifier. No capability lists are compared; no credentials are read.
    
4. **Settlement:** The agent signs the result hash with the registered wallet key. Escrow is released once the signature is verified against the registry.
    

### 7. Generalizing the Construction

The disclosure problem solved by SAP appears in multiple high-stakes infrastructure contexts.

- **Bridge Relayers:** Proving authorization for a specific (chain, message) pair without revealing the entire routing table.
    
- **DAO Voting:** Proving delegation for a proposal category while masking the total delegation boundary from governance competitors.
    
- **Rollup Operators:** Verifying specific operational permissions within a sequencer set without exposing the full permission window to observers.
    

Project Emtun moves this from a theoretical ideal to a validated primitive. The goal is to extract the authorization SDK as a standalone package for the broader agent economy.