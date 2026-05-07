# Emtun Roadmap

## Current Phase

Emtun is in local simulation. The working path includes SAP circuit validation, verifier integration, chain-head policy roots, EAS-style identity attestation, task authorization, escrow funding, requester acceptance, and settlement release.

## Near-Term Work

- Harden settlement and lifecycle invariants.
- Expand contributor documentation.
- Add clearer SDK boundaries around the authorization reader and verifier adapter.
- Improve public diagrams and reproducible screenshots.
- Resolve the production leaf schema question before registry finalization.

## Production Questions

- Should `action_type` remain flat or become a hierarchical capability path?
- What EAS schema should represent the registry and chain-head identity boundary?
- How should verifier gas cost shape aggregation strategy?
- What should the authorization SDK expose to external agent platforms?

## Explicit Non-Goal

Emtun V1 does not prove execution correctness. That requires a separate primitive.
