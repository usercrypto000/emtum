# SAP Fixture Audit
*May 2026*

`sap-fixture-audit.ts` validates the exported verifier-call fixture before it is used by contracts or reviewers. The audit checks schema, field order, public input count, public input mapping, decimal-to-bytes32 conversion, proof byte length, and proof hash metadata. This keeps the public fixture reproducible instead of treating generated JSON as trusted output.
