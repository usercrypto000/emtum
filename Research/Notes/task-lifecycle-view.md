# Task Lifecycle View
*May 2026*

`TaskLifecycleView` provides a read-only snapshot across task intent, escrow, result, and acceptance state. It does not introduce authority, settlement logic, or new trust assumptions. The purpose is client-side observability: indexers and frontends can read one canonical lifecycle shape while the write authority remains split across the market, escrow, result, and acceptance contracts.
