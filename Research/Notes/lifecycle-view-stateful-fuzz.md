# Lifecycle View Stateful Fuzz
*May 2026*

`TaskLifecycleViewStatefulFuzz` runs randomized settlement lifecycle operations and checks that the read-only lifecycle snapshot mirrors the underlying market, escrow, result, and acceptance contracts. The invariant protects observability from drifting away from canonical state.
