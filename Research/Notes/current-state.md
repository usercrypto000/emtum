# Emtun Current State
*May 2026*

This repository currently validates the core SAP construction, not the full marketplace. The active Noir circuit in [circuit/src/main.nr](/C:/Users/HP/KnoxOS/projects/entum/circuit/src/main.nr) proves that a private permission tuple hashes to a public `action_hash` and that `action_hash` is included in a public `policy_root` through a private depth-8 Poseidon2 Merkle path. The local helper in [circuit/src/merkle.nr](/C:/Users/HP/KnoxOS/projects/entum/circuit/src/merkle.nr) replaces the removed `std::merkle` module and keeps Poseidon2 consistent across leaf and internal-node hashing.

## Rerunnable Checks

From [scripts](/C:/Users/HP/KnoxOS/projects/entum/scripts):

```bash
npm run typecheck
npm run poseidon-align
npm run merkle-inclusion
npm run validate
```

From [circuit](/C:/Users/HP/KnoxOS/projects/entum/circuit):

```bash
nargo test
nargo compile
```

## What Is Proven

- Poseidon2 leaf hashing is aligned between TypeScript and the current inclusion circuit.
- Merkle inclusion succeeds for a valid leaf and fails for a rogue action hash.
- The public input surface remains minimal: `policy_root` and `action_hash` only.

## What Is Not Built Yet

- `AgentRegistry`
- chain-head root management contract
- verifier integration contract
- marketplace / escrow contracts
- gas benchmarking for the generated verifier

## Next Best Engineering Step

Generate the verifier from the validated circuit, measure gas on local EVM or testnet, and use that baseline to scope proof aggregation as a later milestone.
