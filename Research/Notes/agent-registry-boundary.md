# Agent Registry Boundary
*May 2026*

`AgentRegistry` is intentionally only an identity ownership boundary. Registration creates an `agentId`, opens the corresponding `PolicyRootChain`, and transfers policy-root control to the registering account. The registry does not verify proofs, assign tasks, hold escrow, or make marketplace decisions; policy authorization remains a composition of the chain head and the SAP verifier path. The integration test now covers the full local SAP flow: registered agent, current root lookup, proof verification, and rejection after root rotation.
