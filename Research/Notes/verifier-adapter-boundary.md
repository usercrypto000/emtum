# Verifier Adapter Boundary
*May 2026*

Emtun contracts should call `EmtunVerifierAdapter.verifyAuthorization(proof, policyRoot, actionHash)` rather than the generated Barretenberg verifier directly. The adapter preserves the SAP boundary by accepting exactly the two circuit-facing public inputs, constructing the verifier input array internally, and returning `false` for invalid proofs instead of exposing generated verifier revert details. This keeps registry and marketplace logic coupled to the Emtun authorization primitive, not to a specific verifier generator output.
