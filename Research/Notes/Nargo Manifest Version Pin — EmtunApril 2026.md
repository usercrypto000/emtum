
The `circuit/Nargo.toml` manifest pins `compiler_version = "1.0.0"` despite the actual nargo binary being `1.0.0-beta.19`. This is not a mismatch. Noir's manifest semver handling strips prerelease metadata (the `-beta.19` suffix) before resolving the version constraint, so `"1.0.0"` is the correct and stable pin for this binary. Writing `"1.0.0-beta.19"` in the manifest would cause a resolution failure.

The practical consequence: if the nargo binary is updated to a post-prerelease `1.0.0` stable build, the manifest pin stays valid without modification. If it is updated to `1.0.1` or beyond, the pin needs to change and the Poseidon alignment test must be re-run before any further circuit work continues. Parameterization can shift between nargo minor versions.

Confirmed working at: `nargo 1.0.0-beta.19`, `compiler_version = "1.0.0"`, Barretenberg backend via `bb.js`, Poseidon2 permutation path. All three alignment leaves passed on `npm run poseidon-align`.

Do not update the nargo binary mid-build without re-running the alignment test first.