# Scoped Authorization Proofs: A ZK Primitive for Agent Policy Commitment

Agent identity standards are starting from a useful primitive and stopping one layer too early. ERC-8004 gives agents a portable onchain reference through an identity registry whose `agentURI` resolves to a registration file, while EIP-712 gives wallets and contracts a standardized way to verify typed signed messages bound to a controlling key [[1]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-1 "ERC-8004: Trustless Agents")[[2]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-2 "EIP-712: Typed structured data hashing and signing").

Neither mechanism answers the question that governs counterparty risk once agents start transacting at scale: whether this specific agent is permitted to perform this specific action inside a committed policy boundary, and whether that permission can be verified without revealing everything else the agent is allowed to do. Registration places an agent inside a discoverable namespace. Authentication binds a message to a controlling key or contract account. Authorization is narrower and more operational because action X sits inside policy boundary Y at verification time Z, which is the boundary Scoped Authorization Proofs (SAP) are built to prove.

SAP proves authorization, not execution correctness. A valid proof establishes that an agent is permitted to perform a scoped action under a committed policy set, while correctness of the resulting work remains a separate problem closer to verifiable compute, TEEs, validation markets, or reputation. That separation matters because an authorization proof becomes weaker if it quietly absorbs claims about model behavior, tool use, hidden business logic, or offchain workflow fidelity.

Policy evolution creates the second constraint. A version window that accepts N prior roots looks operationally convenient, but it keeps a compromised authorization boundary enforceable for the full acceptance period. Revocation only matters when stale permission stops working immediately, which is why Project Emtun uses a policy root chain head instead: the agent attestation points to a dynamic head address rather than one static root value, and advancing that head supersedes prior authorization states for new verification.

## Structural Leakage in Deployed Systems

Current agent authorization designs disclose more than the verifier needs because discovery and permission scope are often collapsed into the same public object. ERC-8004 registration files can expose service endpoints, supported trust models, x402 support, OASF skills, domains, and other metadata through `agentURI` before any transaction takes place [[1]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-1 "ERC-8004: Trustless Agents"). That visibility is not neutral in a competitive marketplace because an observer can correlate bid behavior, win rate, task category, and timing against declared capabilities, then infer which permissions are actively monetized and which scopes exist only as unused surface area. The registration file starts doing intelligence work for the adversary.

Flat authorization compounds the problem. x402 makes machine-native settlement easier by letting a server request payment over HTTP 402 and a client return a signed payment payload before the protected resource is served [[3]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-3 "x402 Documentation"). That payment flow is useful, but the permission question usually remains coarser than the policy boundary. The gate verifies whether the request should clear, while the richer question is whether the agent has authority for this exact action under this exact policy root.

ERC-8004 explicitly keeps payments outside the core registry design while showing how x402 payment evidence can enrich feedback signals, so the two layers can compose without solving the same problem [[1]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-1 "ERC-8004: Trustless Agents"). The combined system can still reveal capability shape before the transaction and verify a narrow accept-or-reject condition during the transaction.

Adjacent identity research has already identified fine-grained access control as a requirement for multi-agent systems. Huang et al. propose decentralized identifiers and verifiable credentials carrying capabilities, provenance, behavioral scope, and security posture, which improves portability and issuer accountability [[4]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-4 "A Novel Zero-Trust Identity Framework for Agentic AI"). Selective disclosure work around credential state points in the same direction, but ordinary credential verification still tends to expose the credential contents needed for the authorization decision [[5]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-5 "EU Web3 Passport"). The verifier does not need a richer public capability map; a stronger primitive gives the verifier confidence that one authorization claim exists under the current policy boundary while unrelated permissions remain hidden.

## The SAP Construction

A policy set in SAP is represented as a fixed-depth Merkle tree. Each leaf commits to one scoped permission using Poseidon2:

```text
Leaf = Poseidon2(action_type, scope, expiry, agent_salt)
```

The tuple is intentionally small. `action_type` captures what the agent may do, `scope` captures the resource boundary, `expiry` gives the authorization a temporal edge, and `agent_salt` prevents direct correlation across low-entropy permission vocabularies.

The circuit exposes only two public inputs:

```text
policy_root
action_hash
```

Every other value remains private witness material: the leaf preimage, sibling path, and path indices. A valid proof enforces two constraints inside the circuit: (a) the private scoped-action tuple hashes to the public `action_hash`, and (b) `action_hash` is included in `policy_root` through the private Merkle path. The verifier learns that the requested action commitment exists under the committed policy root, without reading the full policy set, inspecting sibling leaves, or receiving the salt, which is the authorization primitive.

Per-leaf salting is not decorative. Production action vocabularies cluster around predictable operations such as bridge relay, API call, proposal vote, tool invocation, or model route. A tree-level salt can reduce cross-agent equivalence checks, but it does not isolate repeated structures inside one policy set as cleanly as independent leaf salts.

SAP keeps the salt inside the witness. The verifier gets membership without receiving the preimage material that would make dictionary correlation easy, so discovery and authorization separate cleanly under this model. An agent can advertise a coarse service category in the registry, such as research, execution, trading analysis, or content generation, while the granular policy boundary stays committed inside the Merkle root. A task can specify an `action_hash`, and only agents whose policy sets contain that scoped action can generate a valid proof, which means matching happens against the task requirement rather than a public capability map.

## Poseidon Alignment Is The Critical Path

The construction fails if the offchain tree builder and the circuit disagree about the hash function. Emtun currently uses Noir for the authorization circuit, Barretenberg for proof generation and verification, and TypeScript scripts for Poseidon2 alignment and Merkle inclusion testing, while Poseidon2 sits at the leaf layer and the internal node layer [[6]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-6 "Noir Documentation").

Mixed hash logic breaks prover-verifier consistency. Every downstream contract or marketplace claim therefore depends on hash alignment being treated as a security precondition rather than an implementation chore.

The Noir implementation initializes Poseidon2 state manually with input-length domain separation, using one domain for four-field leaf hashing and another for two-field internal pair hashing. TypeScript reproduces the same construction through Barretenberg, then checks the Noir output against the offchain tree builder. The local Merkle helper exists because the documented Nargo environment does not expose the standard Merkle helper needed here, so `hash_pair` and `compute_merkle_root` become part of the proof surface.

Project notes document successful alignment across three test leaves and a Merkle inclusion run over a five-leaf policy tree, including a negative case that rejects a rogue leaf. Those results make SAP executable rather than purely conceptual, but they remain local-environment claims. Any change to Nargo, Noir, Barretenberg, or hash logic should trigger the same alignment and inclusion tests before contract work continues.

The development order follows from that dependency. Poseidon2 alignment is the first gate, Merkle inclusion is the second, verifier generation is the third, and marketplace work only becomes meaningful after verifier benchmarking. `Counter.sol` in the current Foundry scaffold is disposable, not protocol surface.

## Policy Evolution Requires A Chain Head

A static root works for a demo and fails for a live authorization system. Real agents rotate keys, gain upstream permissions, lose delegated access, deprecate tools, change model routes, and revoke scopes after compromise events, so the policy root needs to evolve without forcing every identity attestation to be reissued.

The naive design accepts a small window of prior roots. That looks convenient until the revoked root is the one that matters, because a compromised authorization boundary remains enforceable for as long as the verifier accepts it. Version windows make stale permissions part of the protocol.

Project Emtun avoids that model with a policy root chain head. The EAS attestation points to a head address, each new root links to its predecessor and increments a version counter, and the marketplace reads the current root from the head at verification time. Historical roots remain available for audit, but new task acceptance depends only on the current root, because revocation should be immediate at the authorization layer. Eventual consistency is the wrong mental model for permission boundaries.

## Emtun Is The Simulation, SAP Is The Primitive

Project Emtun is an agent service marketplace simulation, but the marketplace is not the full product boundary. The current repository uses Noir in `circuit/`, TypeScript tooling in `scripts/`, Barretenberg through `@aztec/bb.js`, and a placeholder Foundry scaffold in `contracts/`, so the simulation exists to validate the primitive before contract architecture gets treated as real protocol design [[6]](https://knoxbt.xyz/research/scoped-authorization-proofs-zk-primitive-agent-policy-commitment#post-source-6 "Noir Documentation").

Leaf schema is the unresolved production decision. The current flat tuple is circuit-friendly and easy to test, but broad authorization domains may need a hierarchical capability path if the number of leaves becomes too large or if scopes need inheritance across namespaces. That decision must be made before finalizing the registry, attestation schema, SDK encoding, or verifier expectations, because deployed policy roots inherit the semantics of the leaf encoding.

Proof caching is the strongest reason to preserve public input minimalism. Because the circuit exposes only `policy_root` and `action_hash`, agents can precompute proofs for frequently requested actions while the current root remains valid. Competitive marketplaces punish latency, and proof generation time matters when several agents are trying to bid on the same task. Adding task-specific public data to the circuit would reduce reuse and push more proving work into the bidding path.

The production product should therefore become an authorization SDK, not only a marketplace. Reuse lives in the registry interface, ZK inclusion circuit, chain-head resolution pattern, verifier integration, canonical action encoding, and documentation for agent platforms that already have their own identity or reputation layer. SAP becomes infrastructure when another system can adopt the authorization primitive without adopting the entire Emtun marketplace.

## Scope Boundary

SAP proves authorization, and that boundary has to stay narrow because the credibility of the primitive depends on not smuggling execution guarantees into an authorization proof. A valid proof tells the verifier that the agent is authorized for the requested action under the current committed policy root. It does not prove that the agent used the right model, interpreted the task correctly, respected hidden business logic, returned a truthful answer, or executed an offchain workflow faithfully. Reputation attestations can punish bad execution after the fact, and future systems may pair SAP with TEEs or verifiable compute for narrower workloads, but those mechanisms carry separate trust assumptions.

The same structure appears outside agent marketplaces. Bridge relayers may need to prove authorization for one message type and source-chain pair without revealing the full routing table. DAO delegates may need to prove authority over one proposal category without exposing their total mandate. Rollup operators may need to prove a specific permission, such as forced-inclusion handling, without publishing every operational capability to competing operators.

Each case shares the same authorization shape: a verifier needs confidence about one action, the prover wants to hide the rest of its permission boundary, and the system needs revocation without stale-root acceptance. SAP fits that shape because it makes authorization scope the cryptographic object.

Project Emtun's contribution is deliberately narrower than a full agent trust stack. Discovery stays with registration, key control stays with authentication, post-execution judgment stays with reputation, and execution correctness stays outside the authorization proof. SAP fills the missing layer between identity and execution, where the agent proves that one scoped action is permitted under one current policy root without exposing the rest of its policy set.