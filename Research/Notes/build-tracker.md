# Emtun Build Tracker
*May 2026*

This tracker records the public simulation builds for Emtun. Each build must preserve the main boundary: Emtun proves scoped authorization against a committed policy root, not execution correctness.

| Build | Commit | Status | What Changed | What It Proves | Screenshot Command |
| --- | --- | --- | --- | --- | --- |
| 01. Scaffold and SAP circuit baseline | `ca95754` | Shipped | Project scaffold, Noir circuit package, Foundry surface, TypeScript proof tooling, Poseidon2 leaf alignment, Merkle inclusion harness | TypeScript and Noir agree on the Poseidon2 leaf hash, the inclusion proof verifies locally, and negative Merkle cases fail | `cd scripts; npm run validate` |
| 02. Repo sync with validated SAP state | `c7956ea` | Shipped | Public repo cleanup and validated SAP state documentation | The repo can be cloned and rerun around the core SAP proof path | `cd scripts; npm run validate` |
| 03. Verifier gas baseline | `5254c1c` | Shipped | EVM verifier fixture and gas measurement | A single Barretenberg verifier call is measurable and expensive enough to justify future aggregation work | `cd contracts; forge test --match-path test/VerifierGas.t.sol -vvv` |
| 04. Verifier adapter boundary | `edf2011` | Shipped | Adapter around the generated Honk verifier | Contracts call the stable SAP interface, not generated verifier internals | `cd contracts; forge test --match-path test/EmtunVerifierAdapter.t.sol -vvv` |
| 05. Policy root chain | `63eabb6` | Shipped | Chain-head policy root contract with historical records and no version window | Only the current root is valid for authorization; older roots remain historical but not accepted | `cd contracts; forge test --match-path test/PolicyRootChain.t.sol -vvv` |
| 06. Authorization reader | `ad94d05` | Shipped | Current-root lookup plus proof verification reader | Stale proofs fail after policy root rotation | `cd contracts; forge test --match-path test/EmtunAuthorizationReader.t.sol -vvv` |
| 07. Agent registry boundary | `e17ffb7` | Shipped | Agent registration and ownership boundary | Agent identity exists separately from policy evolution | `cd contracts; forge test --match-path test/AgentRegistry.t.sol -vvv` |
| 08. EAS attestation boundary | `6719a69` | Shipped | Local EAS mock and identity attestation boundary | Identity attestation points to the registry and chain-head mechanism, not one root value | `cd contracts; forge test --match-path test/EmtunEASAttestationBoundary.t.sol -vvv` |
| 09. Task authorization gate | `8d2cd7d` | Shipped | Gate combining registration, active attestation, and SAP verification | A task-level authorization check passes only when identity and current-root authorization both hold | `cd contracts; forge test --match-path test/TaskAuthorizationGate.t.sol -vvv` |
| 10. Owner transfer attestation invalidation | `0208f42` | Shipped | EAS boundary binds active attestation to current registry owner | Owner transfer invalidates usable identity attestation until the new owner re-attests | `cd contracts; forge test --match-path test/EmtunEASAttestationBoundary.t.sol -vvv` |
| 11. Full authorization lifecycle smoke | `e26de0f` | Shipped | Single smoke test logging the full lifecycle | Register, attest, authorize, reject stale root, invalidate on transfer, and re-attest all work in one auditable path | `cd contracts; forge test --match-path test/EmtunSimulationSmoke.t.sol -vvv` |
| 12. Task intent market | `6629094` | Shipped | Requester task intents and owner-gated agent claims through SAP authorization | A task can be assigned only when the current agent owner submits the claim and SAP authorization verifies | `cd contracts; forge test --match-path test/EmtunSimulationSmoke.t.sol -vvv` |
| 13. Build tracker | `5b39f7a` | Shipped | Public tracker for shipped builds, proof claims, and screenshot commands | The project now has a canonical development ledger before escrow or execution work begins | `cd contracts; forge test --match-path test/EmtunSimulationSmoke.t.sol -vvv` |

## Open Build Queue

- Escrow should stay blocked until the assignment boundary is stable and documented.
- Execution verification remains out of scope for V1 unless a separate primitive is introduced.
- Production leaf schema remains unresolved; changing it after deployment invalidates all policy commitments.
- Recursive aggregation remains a later verifier economics milestone, not a simulation blocker.
