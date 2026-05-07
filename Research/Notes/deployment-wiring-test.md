# Deployment Wiring Test
*May 2026*

`DeploySimulation.t.sol` checks that every deployed simulation contract has code and that constructor dependencies point to the intended addresses. This protects the deployment script from dependency drift as the marketplace surface expands. The test does not introduce production deployment semantics; it only validates the local simulation wiring.
