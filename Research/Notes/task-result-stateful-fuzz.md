# Task Result Stateful Fuzz
*May 2026*

`TaskResultRegistryStatefulFuzz` covers task opening, claiming, cancellation, owner transfer, valid result commits, and rejected commit attempts. The invariant is that only the current owner of the assigned agent can commit one nonzero result hash for an assigned task. This protects the accountability record while keeping result submission separate from settlement and execution verification.
