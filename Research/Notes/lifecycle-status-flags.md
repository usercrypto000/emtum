# Lifecycle Status Flags
*May 2026*

`TaskLifecycleView` now exposes boolean status flags alongside enum values. The flags make frontend and SDK reads less error-prone while leaving the source of truth unchanged. Intent, escrow, result, and acceptance contracts still own state; the lifecycle view only mirrors it.
