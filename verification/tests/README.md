# Verification work-directory regression

This test uses tiny built Lean projects and the unchanged comparator runner. It
needs Python 3, Lean 4.33.1 on `PATH`, and the two comparator/exporter source
checkouts built as described in `verification/comparator/run.sh`:

```sh
COMPARATOR_SRC=/absolute/path/to/comparator \
LEAN4EXPORT_SRC=/absolute/path/to/lean4export \
python3 -m unittest discover -s verification/tests -p test_work_root.py -v
```

The runner builds the tools if needed, pins them to Lean 4.33.1, and configures
comparator to use the exporter checkout. The v4.33.0 tags identify the tested
sources: comparator `3927ad383f208ae977c340a91c48ac9b497d2097` and
lean4export `15f6055e299ad5b89345e533cc2192f4cc00f659`.
The fixture has an empty library named Mathlib to satisfy the wrapper's input
layout; its proofs use only Lean core. No full FLT build or Hypothesis is needed.

On unchanged upstream, three controls pass and
`test_reused_work_must_not_accept_previous_tree` fails. It first verifies a
valid tree A, then verifies tree B with the same explicit `WORK`. B uses an axiom
excluded by `permitted_axioms`, but the old A symlink remains and the runner
exits zero. The same B is rejected with a fresh work directory; editing and
rebuilding A at its existing path is also correctly observed.

This is an input-artifact attribution regression requiring cross-checkout
`WORK` reuse. It does not demonstrate a defect in either proof kernel, a failure
on the default fresh work directory, or a problem with the published FLT proof.
The tests may use comparator's ordinary fake-landrun fallback, just as the
upstream wrapper does for locally built sources.
