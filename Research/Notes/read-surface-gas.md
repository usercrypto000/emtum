# Read Surface Gas
*May 2026*

`ReadSurfaceGas.t.sol` records gas for the SDK-facing authorization status view and task lifecycle view. The authorization status read includes proof verification, so it remains expensive by design. The lifecycle view is a lightweight observability read over existing task state.
