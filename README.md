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
- `npm run generate:verifier` generates the EVM verifier and a reusable proof fixture for the current circuit.
- `npm run export:verifier-call` exports an auditable verifier-call fixture from the generated proof.
- `contracts/` contains the generated Honk verifier, verifier adapter, policy root chain, agent registry boundary, EAS-facing attestation mock, authorization reader, authorization status view, task authorization gate, task intent market, task funding escrow, task result registry, task acceptance registry, read-only lifecycle view, deployment script, and Foundry tests. Escrow release is gated by requester acceptance. Execution verification has not been implemented.

## Structure

- `circuit/`: Noir inclusion circuit, local Poseidon2 Merkle helper, and compiled artifacts
- `contracts/`: Foundry surface, generated verifier, verifier adapter, policy root chain, agent registry boundary, EAS-facing attestation mock, authorization reader, authorization status view, task authorization gate, task intent market, task funding escrow, task result registry, task acceptance registry, read-only lifecycle view, deployment script, SDK read interfaces, and verifier gas tests
- `scripts/`: TypeScript proof tooling and rerunnable validation harnesses
- `Research/`: architectural notes, drafts, and publication planning
- `lib/` and `test/`: reserved for future shared modules and fixtures

## Build Tracker

The public build ledger lives at [Research/Notes/build-tracker.md](C:/Users/HP/KnoxOS/projects/entum/Research/Notes/build-tracker.md). Each shipped build records the commit, proof claim, and screenshot command.

## Key Commands

From [scripts](C:/Users/HP/KnoxOS/projects/entum/scripts):

```bash
npm run typecheck
npm run poseidon-align
npm run merkle-inclusion
npm run generate:verifier
npm run export:verifier-call
npm run sap-fixture-audit
npm run validate
```

From [circuit](C:/Users/HP/KnoxOS/projects/entum/circuit):

```bash
nargo test
nargo compile
```

From [contracts](C:/Users/HP/KnoxOS/projects/entum/contracts):

```bash
forge test -vvv
forge test --match-path test/EmtunSimulationSmoke.t.sol -vvv
forge test --match-path test/TaskFundingEscrow.t.sol -vvv
forge test --match-path test/TaskResultRegistry.t.sol -vvv
forge test --match-path test/TaskAcceptanceRegistry.t.sol -vvv
forge test --match-path test/TaskLifecycleView.t.sol -vvv
forge test --match-path test/EmtunAuthorizationStatusView.t.sol -vvv
forge test --match-path test/DeploySimulation.t.sol -vvv
forge test --match-path test/SdkReadInterfaces.t.sol -vvv
forge test --match-path test/ReadSurfaceGas.t.sol -vvv
forge test --match-path test/PrimitiveBoundarySmoke.t.sol -vvv
forge test --match-path test/TaskIntentMarketStatefulFuzz.t.sol -vvv
forge test --match-path test/TaskFundingEscrowStatefulFuzz.t.sol -vvv
forge test --match-path test/TaskResultRegistryStatefulFuzz.t.sol -vvv
forge test --match-path test/TaskAcceptanceRegistryStatefulFuzz.t.sol -vvv
forge test --match-path test/TaskSettlementStatefulFuzz.t.sol -vvv
forge test --match-path test/TaskLifecycleViewStatefulFuzz.t.sol -vvv
forge script script/DeploySimulation.s.sol:DeploySimulation
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
- deployable verifier baseline uses `optimizer_runs = 1`, measures one proof at 2,164,576 gas, and keeps runtime bytecode under the EIP-170 size ceiling
- future contracts call the verifier adapter, not the generated Barretenberg verifier directly
- `PolicyRootChain` stores historical roots for auditability, but only the current chain head passes authorization checks
- `AgentRegistry` owns `agentId` existence, then delegates policy updates to `PolicyRootChain`
- `EmtunEASAttestationBoundary` attests to the registry and chain-head mechanism, not to a single policy root value, and treats owner transfer as an attestation invalidation boundary until the new owner re-attests
- `EmtunAuthorizationReader` composes the current root lookup with proof verification and rejects stale roots after rotation
- `EmtunAuthorizationStatusView` exposes a read-only SDK snapshot for registration, attestation, current root, and proof authorization state
- `PrimitiveBoundarySmoke` logs the core SAP public claim without introducing execution correctness or settlement semantics
- `TaskAuthorizationGate` combines registration, active identity attestation, and SAP proof validity without adding marketplace execution semantics
- `TaskIntentMarket` lets requesters open task intents and lets agents claim them only after `TaskAuthorizationGate` accepts authorization, without adding escrow or execution verification
- `TaskFundingEscrow` lets requesters fund open task intents, recover funds after cancellation, and release escrow to the current assigned agent owner only after requester acceptance
- `TaskResultRegistry` lets assigned agents commit output hashes without proving execution correctness or triggering settlement
- `TaskAcceptanceRegistry` lets requesters accept committed result hashes without turning acceptance into execution verification
- `TaskLifecycleView` gives clients one read-only task snapshot across intent, escrow, result, acceptance, status flags, and audit timestamp state

## Immediate Next Milestones

1. Keep the repo rerunnable and internally consistent with the draft.
2. Resolve production leaf-schema direction before real registry work.
3. Continue rewriting the research draft into publishable form while the implementation stays narrow and testable.
