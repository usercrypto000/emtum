# Task Acceptance Registry
*May 2026*

`TaskAcceptanceRegistry` lets the requester accept the exact `resultHash` previously committed by the assigned agent owner. Acceptance is an explicit requester state transition, not a cryptographic proof that the result is correct. This creates a clean future predicate for settlement work while preserving the V1 boundary: Emtun proves authorization, records result commitments, and records requester acceptance, but it still does not verify execution correctness.
