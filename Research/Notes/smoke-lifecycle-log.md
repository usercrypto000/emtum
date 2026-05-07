# Smoke Lifecycle Log
*May 2026*

The full simulation smoke test now logs the lifecycle escrow status after settlement release. `Released` is encoded as status `3`, matching the `TaskFundingEscrow.EscrowStatus` enum. The log gives the public demo path a compact screenshot target after funding, claim, result commit, acceptance, and settlement release.
