# Lifecycle Audit Fields
*May 2026*

`TaskLifecycleView` now exposes the requester, escrow payer, assigned agent, result agent, escrow amount, and lifecycle timestamps in one read-only snapshot. The view still has no write authority. Its purpose is observability for clients, indexers, and public screenshots, not settlement logic.
