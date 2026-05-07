# Payout Failure Coverage
*May 2026*

`TaskFundingEscrow` now has explicit regression coverage for recipients that reject ETH. If the current assigned agent owner cannot receive payment, release reverts and the escrow record remains funded. This keeps settlement accounting atomic: a failed payout cannot mark a task as paid.
