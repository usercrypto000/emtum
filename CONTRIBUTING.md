# Contributing to Emtun

Emtun is a research simulation for Scoped Authorization Proofs. The project proves scoped authorization against committed policy roots. It does not prove execution correctness.

## Useful Contributions

- Noir circuit review.
- Barretenberg verifier integration review.
- Solidity marketplace hardening.
- Stateful fuzz coverage.
- EAS identity boundary review.
- Agent authorization taxonomy design.
- Documentation that clarifies trust boundaries.

## Review Standard

Good review is mechanism-level. Point to the exact boundary, constraint, state transition, or test invariant that needs attention. Broad comments are less useful than one precise failure mode.

## Local Verification

From `scripts`:

```bash
npm run validate
```

From `circuit`:

```bash
nargo test
```

From `contracts`:

```bash
forge test -vvv
forge script script/DeploySimulation.s.sol:DeploySimulation
```

## Scope Boundary

Do not frame Emtun as execution verification. A valid contribution preserves the distinction between identity, authorization, settlement, and execution correctness.
