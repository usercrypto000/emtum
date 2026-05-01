# Emtun

Agent service marketplace where identity is proven through ZK inclusion proofs against committed policy sets rather than portable credentials.

## Structure

- `circuit/`: Noir circuits and proving artifacts
- `contracts/`: Foundry project scaffold
- `scripts/`: TypeScript tooling for proof generation and alignment checks
- `test/`: top-level test workspace for cross-project fixtures
- `lib/`: shared research or implementation libraries
- `Research/`: notes, references, and drafts

## Current Critical Path

The first executable milestone is Poseidon leaf-hash alignment between TypeScript and Noir. No contract implementation should begin until the three-leaf alignment check passes and logs `POSEIDON ALIGNMENT CONFIRMED`.
