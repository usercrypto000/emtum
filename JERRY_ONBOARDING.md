# Jerry Onboarding: Emtun

This is the project brief for Jerry. It extracts the current technical state, product intent, constraints, and next steps from the files in this folder.

## Custom GPT Instruction Block

Use this if Jerry needs a short instruction payload:

```text
You are Jerry, the project copilot for Emtun.

Emtun is building Scoped Authorization Proofs (SAP): a ZK primitive that lets an AI agent prove authorization for one scoped action without revealing its full policy set. The current repo is a local simulation using Noir, Barretenberg, TypeScript, and a placeholder Foundry contracts scaffold.

Your priorities:
1. Preserve the distinction between registration, authentication, scoped authorization, and execution correctness.
2. Remember that Emtun proves authorization, not execution correctness.
3. Treat Poseidon2 alignment between TypeScript and Noir as the current critical path.
4. Do not begin real contract implementation until Poseidon alignment and Merkle inclusion checks pass.
5. Preserve minimal public inputs in the circuit: policy_root and action_hash only.
6. Treat the production policy root chain head as required. Do not recommend a version window that accepts old roots.
7. Treat contracts/src/Counter.sol as disposable Foundry scaffold.
8. Treat Research/Drafts/part-one-draft.md as raw research material that needs formal academic rewriting.
9. Re-run alignment after any Nargo, Noir, Barretenberg, or hash-logic change.

Core construction:
Leaf = Poseidon2(action_type, scope, expiry, agent_salt)
The circuit proves that action_hash matches the private leaf preimage and that action_hash is included in policy_root through a private Merkle path.

Current stack:
- Noir circuit in circuit/
- TypeScript proof and alignment scripts in scripts/
- Barretenberg through @aztec/bb.js
- Foundry scaffold in contracts/
- Research notes and drafts in Research/

Important commands:
cd scripts && npm run typecheck
cd scripts && npm run poseidon-align
cd scripts && tsx test/merkle-inclusion.ts
cd contracts && forge test
cd circuit && nargo check
cd circuit && nargo compile
```

## Project Identity

Emtun is an agent service marketplace and authorization primitive. Its core idea is that an AI agent should be able to prove it is authorized for a specific action without revealing its entire policy or capability set.

The project frames this as Scoped Authorization Proofs, or SAP:

- Identity/registration proves an agent exists.
- Authentication proves the agent controls a registered key.
- SAP proves the agent is authorized for one scoped action.
- SAP does not prove execution correctness.

The present repository is a local simulation and research workspace. The current executable milestone is Poseidon leaf-hash alignment between TypeScript and Noir, followed by Merkle inclusion proof validation.

## Repository Layout

- `README.md`: top-level project summary and critical path.
- `circuit/`: Noir circuit source and generated circuit artifact.
- `circuit/src/main.nr`: main authorization circuit.
- `circuit/src/merkle.nr`: local Merkle root helper using Poseidon2.
- `circuit/target/circuit.json`: compiled Noir circuit artifact used by TypeScript scripts.
- `contracts/`: Foundry scaffold. Currently only a default `Counter` contract and tests.
- `scripts/`: TypeScript tooling for proof generation, hash alignment, and Merkle inclusion checks.
- `Research/Notes/`: architectural decisions and implementation notes.
- `Research/Drafts/`: research article outline and draft.
- `Research/References/`: currently empty.
- `lib/` and `test/`: currently empty top-level folders.

There is no active Git repository detected from this folder.

## Current Critical Path

Do not start meaningful contract implementation until Poseidon alignment is confirmed.

The top-level `README.md` states the first milestone clearly: TypeScript and Noir must agree on Poseidon leaf hashes for three leaf cases, and the script must log:

```text
POSEIDON ALIGNMENT CONFIRMED
```

The next executable validation is Merkle inclusion. The script should log:

```text
MERKLE INCLUSION CONFIRMED
NEGATIVE CASE CONFIRMED
```

## Core Construction

The policy set is represented as a fixed-depth Merkle tree. Each leaf commits to one scoped permission:

```text
Leaf = Poseidon2(action_type, scope, expiry, agent_salt)
```

The circuit proves two things:

- The public `action_hash` matches the private leaf preimage.
- The public `policy_root` matches the root computed from `action_hash`, a private Merkle path, and private path indices.

Only `policy_root` and `action_hash` are public. The leaf preimage, sibling path, and index bits are private.

## Circuit Details

Files:

- `circuit/Nargo.toml`
- `circuit/src/main.nr`
- `circuit/src/merkle.nr`

The Noir package is named `circuit`, has type `bin`, and pins:

```toml
compiler_version = "1.0.0"
```

This is intentional even though the working binary is documented as `nargo 1.0.0-beta.19`. Noir's manifest semver handling strips prerelease metadata, so `1.0.0` is the stable pin. Do not change this casually.

The circuit uses tree depth 8, supporting 256 policy leaves.

Public inputs:

- `policy_root: pub Field`
- `action_hash: pub Field`

Private inputs:

- `action_type: Field`
- `scope: Field`
- `expiry: Field`
- `agent_salt: Field`
- `path: [Field; 8]`
- `indices: [u1; 8]`

`main.nr` defines a local `leaf_hash` using `std::hash::poseidon2_permutation`. It initializes the Poseidon2 state manually with an input-length domain separator:

- leaf hash uses `iv = 4 * 2^64`
- pair hash uses `iv = 2 * 2^64`

`merkle.nr` defines:

- `hash_pair(left, right)`
- `compute_merkle_root(leaf, path, indices)`

`std::merkle` is not available in `nargo 1.0.0-beta.19`, so this local helper is intentional.

## TypeScript Tooling

Files:

- `scripts/package.json`
- `scripts/tsconfig.json`
- `scripts/test/poseidon-align.ts`
- `scripts/test/merkle-inclusion.ts`

The scripts package is private, ESM-based, and uses:

- Node.js / TypeScript
- `tsx`
- `@aztec/bb.js`
- `@noir-lang/noir_js`

Available npm scripts from `scripts/package.json`:

```bash
npm run poseidon-align
npm run typecheck
```

Run these from the `scripts/` directory.

`poseidon-align.ts`:

- Loads `../circuit/target/circuit.json`.
- Computes Poseidon2 hashes with Barretenberg.
- Executes the Noir circuit for three test leaves.
- Generates and verifies UltraHonk proofs.
- Confirms the Noir return value and public proof output match the TypeScript hash.

`merkle-inclusion.ts`:

- Builds a depth-8 Merkle tree in TypeScript.
- Uses five policy leaves and pads remaining leaves with `0n`.
- Generates a proof for target leaf index `3`.
- Executes the Noir circuit.
- Generates and verifies an UltraHonk proof.
- Runs a negative case using a rogue leaf that should fail.

## Contracts State

Files:

- `contracts/foundry.toml`
- `contracts/src/Counter.sol`
- `contracts/test/Counter.t.sol`
- `contracts/script/Counter.s.sol`

The contracts folder is still a Foundry scaffold. `Counter.sol` is a placeholder and should not be treated as part of the Emtun protocol design.

Foundry commands from the scaffold:

```bash
forge build
forge test
forge fmt
forge snapshot
anvil
```

Expected future contracts from the research notes:

- `AgentRegistry`
- marketplace/escrow contract
- policy root chain head contract
- Barretenberg verifier integration
- EAS attestation integration
- ERC-8004 registration reference integration

## Product And Research Model

The project argues that current agent identity systems conflate several layers:

- existence/registration
- authentication
- authorization scope
- execution correctness

Emtun focuses on authorization scope.

The disclosure problem:

- Public capability files reveal an agent's entire authorization boundary.
- Boolean allowlists are too coarse.
- Verifiable Credentials still disclose credential contents to verifiers.

SAP's answer:

- Commit the full policy set as a Merkle root.
- Prove inclusion of one authorized action in zero knowledge.
- Reveal only the root and action hash.

## Production Architectural Constraints

These decisions come from `Research/Notes/production-constraints.md`.

### Leaf Schema

Current simulation uses a flat tuple:

```text
(action_type, scope, expiry, agent_salt)
```

Flat capabilities are simple and circuit-friendly, but broad authorization means many leaves. A hierarchical capability path may be better for production, but it requires more complex circuit logic and a frozen taxonomy.

Production decision unresolved: flat or hierarchical capabilities.

This must be decided before finalizing `AgentRegistry`, because changing leaf schema after deployment invalidates existing policy commitments.

### Policy Root Chain Head

Production must not bind an EAS attestation directly to one static policy root.

Instead:

- each agent has a chain head pointer;
- each new root points to its predecessor;
- each new root has a monotonic version counter;
- the EAS attestation points to the chain head address;
- marketplace verification resolves the current root at verification time.

Do not implement a version window that accepts older roots. Old-root validity keeps compromised permissions alive.

### Proof Caching

Proof generation can take several seconds. In a competitive marketplace, latency matters.

Production agents should precompute proofs for frequently claimed action types. This is only valid while the policy root remains current.

The current circuit supports caching because public inputs are only `policy_root` and `action_hash`; there is no task-specific public data.

Preserve that separation.

### Gas Cost

Single Barretenberg verifier calls are expected to be expensive. Production likely needs recursive proof aggregation after the single-proof circuit is finalized.

Before aggregation work, generate the verifier contract and benchmark gas on testnet or local EVM.

### Execution Verification

Execution correctness is explicitly out of scope for Emtun V1.

The system proves authorization, not that an AI agent performed the task correctly. Future versions may pair SAP with TEE-based or verifiable-compute systems, but that is a separate primitive.

### Infrastructure Framing

The marketplace is the proof of concept. The larger product is an authorization SDK:

- registry contract
- ZK inclusion circuit
- verifier integration
- integration docs for other agent platforms

Roadmap framing from the notes:

- V1: local simulation
- V2: testnet marketplace deployment
- V3: standalone authorization SDK

## Research Draft State

Files:

- `Research/Drafts/outline.md.md`
- `Research/Drafts/part-one-draft.md`

The draft currently argues for "Scoped Authorization Proofs: A ZK Primitive for Agent Policy Commitment."

Important caveat: the draft itself ends with the note:

```text
this piece doesn't read like a real research paper

can you fix it
```

So the draft should be treated as raw material, not polished publication copy.

The outline is more structured than the draft and may be the better base for a rewrite.

## Known Working Claims Captured In Notes

Documented successful environment:

- `nargo 1.0.0-beta.19`
- `compiler_version = "1.0.0"`
- Barretenberg through `bb.js`
- Poseidon2 permutation path
- all three alignment leaves passed on `npm run poseidon-align`

Documented Merkle inclusion output from the draft:

```text
policy_root: 20104258940592381864488285159848356485838757592246922495957826745811242706711
action_hash: 6253325843186180020011114696561168856123092894723656686593756597447500122664

MERKLE INCLUSION CONFIRMED
NEGATIVE CASE CONFIRMED
```

These are claims from the project files. Re-run the scripts before relying on them for fresh work.

## Commands For Jerry

From the project root:

```bash
cd scripts
npm run typecheck
npm run poseidon-align
tsx test/merkle-inclusion.ts
```

From the contracts folder:

```bash
cd contracts
forge build
forge test
```

From the circuit folder, if `nargo` is installed:

```bash
cd circuit
nargo check
nargo compile
```

If `nargo` changes version, rerun Poseidon alignment before doing any circuit work.

## Immediate Next Steps

1. Re-run `npm run typecheck`.
2. Re-run `npm run poseidon-align`.
3. Re-run `tsx test/merkle-inclusion.ts`.
4. If all pass, decide whether the next milestone is:
   - generate and benchmark the verifier contract;
   - build the first real Foundry contracts;
   - rewrite the research draft into a formal paper style;
   - design the production leaf schema.
5. Do not implement production registry contracts until the flat-vs-hierarchical leaf schema decision is made.

## Rules Of Thumb For This Project

- Preserve public input minimalism: `policy_root` and `action_hash` only.
- Keep authorization separate from execution correctness.
- Treat the policy root chain head as a production requirement, not an optional optimization.
- Avoid accepting old roots through a version window.
- Re-run alignment after any Noir, Nargo, Barretenberg, or hash-code change.
- Treat `contracts/src/Counter.sol` as disposable scaffold.
- Treat `Research/Drafts/part-one-draft.md` as a draft needing academic cleanup.
- Keep the marketplace framed as one application of a general authorization primitive.
