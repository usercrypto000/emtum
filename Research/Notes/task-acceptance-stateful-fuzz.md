# Task Acceptance Stateful Fuzz
*May 2026*

`TaskAcceptanceRegistryStatefulFuzz` models open, claim, result commit, acceptance, and rejected acceptance attempts across bounded operation sequences. The invariant is that accepted records match the model, acceptance remains requester-only, and accepted hashes stay terminal. This gives the acceptance layer stronger regression coverage without changing the trust model: acceptance is a requester decision, not a proof of execution correctness.
