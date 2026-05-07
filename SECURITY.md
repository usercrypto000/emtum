# Security Policy

Emtun is pre-audit research software. Do not use it in production with real funds.

## Reporting

Open a private security advisory on GitHub if the issue affects authorization soundness, proof verification, escrow accounting, identity attestation validity, or policy root evolution.

For non-sensitive issues, open a public issue with a minimal reproduction.

## Current Security Boundaries

- SAP proves scoped authorization against the current committed policy root.
- The circuit does not prove execution correctness.
- Requester acceptance is the settlement trigger in the simulation.
- Historical policy roots are auditable but not valid for authorization.
- Owner transfer invalidates active identity attestations until the new owner re-attests.

## Out of Scope

- Mainnet deployment assumptions.
- Production key management.
- Recursive proof aggregation.
- General AI execution verification.
