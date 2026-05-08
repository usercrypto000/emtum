# Authorization Status View
*May 2026*

`EmtunAuthorizationStatusView` gives clients one read-only snapshot for an agent authorization check: registration state, active attestation state, current owner, current policy root, registration timestamp, and whether a proof authorizes the requested action. This is an SDK-facing view, not a new trust boundary. The authorization claim still comes from the registry, attestation boundary, chain-head root, and SAP verifier.
