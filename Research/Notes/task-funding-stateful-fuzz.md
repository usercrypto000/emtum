# Task Funding Stateful Fuzz
*May 2026*

`TaskFundingEscrowStatefulFuzz` models requester funding, cancellation, and refunds across bounded operation sequences. The invariant is that escrow balances, payer records, and task statuses stay aligned with the model. Release coverage stays in the focused escrow tests because release depends on the result and acceptance registries, while this fuzz target isolates the funding and cancellation refund surface.
