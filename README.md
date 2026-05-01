# Emtun

Emtun is a local simulation of Scoped Authorization Proofs (SAP), a ZK primitive that lets an AI agent prove authorization for one scoped action without revealing its full policy set.

## What The Repo Currently Proves

- A private leaf preimage `(action_type, scope, expiry, agent_salt)` hashes to a public `action_hash`.
- That `action_hash` is included in a public `policy_root` through a private Poseidon2 Merkle path.
- The circuit exposes only `policy_root` and `action_hash` as public inputs.
- The repo does not prove execution correctness, only scoped authorization.

## Current State

- `npm run poseidon-align` replays Poseidon2 leaf-hash alignment against the current inclusion-circuit ABI and should log `POSEIDON ALIGNMENT CONFIRMED`.
- `npm run merkle-inclusion` builds a depth-8 Poseidon2 Merkle tree, proves inclusion for one leaf, and checks a negative case. It should log `MERKLE INCLUSION CONFIRMED` and `NEGATIVE CASE CONFIRMED`.
- `contracts/` is still scaffold-only Foundry surface. No protocol contracts have been implemented yet.

## Structure

- `circuit/`: Noir inclusion circuit, local Poseidon2 Merkle helper, and compiled artifacts
- `contracts/`: Foundry scaffold only
- `scripts/`: TypeScript proof tooling and rerunnable validation harnesses
- `Research/`: architectural notes, drafts, and publication planning
- `lib/` and `test/`: reserved for future shared modules and fixtures

## Key Commands

From [scripts](C:/Users/HP/KnoxOS/projects/entum/scripts):

```bash
npm run typecheck
npm run poseidon-align
npm run merkle-inclusion
npm run validate
```

From [circuit](C:/Users/HP/KnoxOS/projects/entum/circuit):

```bash
nargo test
nargo compile
```

## Architectural Position

SAP sits between identity and execution:

- registration proves an agent exists
- authentication proves key control
- SAP proves scoped authorization
- execution correctness remains out of scope for Emtun V1

Production design constraints already established in the repo:

- no version window for old policy roots
- policy evolution should use a chain-head pattern
- public inputs must stay minimal to support proof caching
- Poseidon2 must remain consistent at leaf and internal-node levels

## Immediate Next Milestones

1. Keep the repo rerunnable and internally consistent with the draft.
2. Generate and benchmark the verifier contract gas cost.
3. Resolve production leaf-schema direction before real registry work.
4. Continue rewriting the research draft into publishable form while the implementation stays narrow and testable.
