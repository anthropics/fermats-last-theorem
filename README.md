# Fermat's Last Theorem in Lean 4

A complete, machine-checked proof of Fermat's Last Theorem in [Lean 4](https://lean-lang.org), built on
[Mathlib](https://github.com/leanprover-community/mathlib4) (Lean 4.33.1; Mathlib `v4.33.0`, pinned by commit in
`lakefile.lean`). The argument is that of Frey, Serre, Ribet, Wiles and Taylor-Wiles. `PROOF-PATH.md` names each step
and the Lean theorem that carries it, and the `html/` folder presents the whole proof as web pages you can browse
offline (see "Reading the proof in a browser" below).

Research artifact. Not maintained and not accepting contributions.

## The statement

`Theorems/Thm_fermat_last_theorem.lean` declares

~~~lean
theorem fermat_last_theorem (n : ℕ) (hn : 3 ≤ n) (a b c : ℕ) (ha : 0 < a) (hb : 0 < b) (hc : 0 < c) : a ^ n + b ^ n ≠ c ^ n
~~~

and the default build target `FinalCheck.lean` contains

~~~lean
/-- info: 'fermat_last_theorem' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms fermat_last_theorem
~~~

so the build fails unless the proof rests on exactly Lean's three standard axioms (no `sorry`, no added `axiom`,
no `native_decide`). `FinalCheck.lean` also derives Mathlib's own statement, `FermatLastTheorem`, from this theorem.

## How it was verified

- **Build.** A from-scratch `lake build` on Lean 4.33.1 (which includes the 2026 kernel soundness fixes), with
  Mathlib compiled from source. All 60,475 modules of this repository built, every declaration was checked by the
  Lean kernel, and the axioms are as above.
- **comparator.** [leanprover/comparator](https://github.com/leanprover/comparator) `v4.33.0` checked the build against
  `verification/comparator/Challenge.lean`, which states the theorem using only Mathlib. It confirmed that the proved
  statement and every constant it mentions are identical to the challenge, that no other axiom is used, and that the
  whole proof, Mathlib included, replays through the Lean kernel. Verdict: `Your solution is okay!`
- **A second kernel.** [nanoda](https://github.com/ammkrn/nanoda_lib) 0.4.13, an independent Lean kernel written in
  Rust, accepted an export of the same environment (written with lean4export): `Checked 1052234 declarations with no
  errors`. We built nanoda with four small patches of our own (`verification/nanoda/patches/`): one adds progress output and
  three speed up its definitional-equality search, without which a few declarations of this proof occupy unmodified
  nanoda for many hours each. None of the patches adds, removes or weakens a typing rule.

No module contains `axiom`, `sorry`, `native_decide`, `unsafe`, `extern`, `implemented_by`, `partial def` or `#eval`
(`Challenge.lean` uses `sorry` by design and is not part of the package).

Together, these checks establish that the statement above follows from the three axioms, given trust in the Lean
kernel (or nanoda) and the checking tools. The statement is written with Lean's built-in natural numbers, `+`, `≤`, `<`
and `≠`; its one Mathlib ingredient is `^` on ℕ, which Mathlib defines as Lean's built-in exponentiation, and
comparator checks that every definition the statement mentions is identical to stock Mathlib's. Nothing else in
Mathlib has to be trusted, because the kernel checks everything beneath the statement. What no tool can check is that
each intermediate theorem means what its name suggests; that is for the reader to judge, and `PROOF-PATH.md` names
the Lean theorem behind each step and states exactly how strong each named classical result is as proved here.

## Reading the proof in a browser
The documentation is hosted at [Documentation Website](https://tianyipeng.github.io/fermats-last-theorem/).
You can also browse them locally from the `html/` folder of this repository, as follows.

The `html/` folder (about 390 MB) presents this repository as static web pages: the route of the proof step by step;
a page for each of the 29,511 theorems (the exact Lean statement, what it cites and what cites it, and an expandable
dependency graph) and for each of the 1,450 definition modules (the full source and which statements use it); a
search box over all theorem and definition names; the landmark theorems as a graph; and `README.md`, `PROOF-PATH.md`
and `ATTRIBUTION.md` rendered with cross-links. The folder is part of this repository, so a clone or a ZIP download
already contains it (if you obtained `html/` as a separate archive, unpack it at the repository root). Open
`html/index.html` in a web browser; everything works offline, with no web server. The pages were machine-tested in a
Chromium-based browser only, and `html/README-DOCS.md` explains what is quoted from the Lean files and what is
generated (the English summaries and suggested references are generated automatically; the Lean statement is
authoritative).

## Check it yourself

- You need Linux or macOS (some paths are too long for Windows), [elan](https://github.com/leanprover/elan) (it
  installs Lean 4.33.1 from `lean-toolchain`), and a network connection: Lake fetches Mathlib from GitHub and compiles
  it from source, since no prebuilt Mathlib matches this toolchain (about 13 minutes at 96 jobs).
- The build needs about 5 GB of memory per parallel job (a few modules need up to 36 GB); about 67 GB of disk under
  `.lake/`, plus C files (about 220 GB) that can be deleted as the build goes. Ours took 5 h 32 min at 96 jobs, with a
  peak of 153 GB of memory.
- comparator takes about 15 hours (ours: 14 h 46 min), nearly all of it the kernel replay on one core. Our peak memory
  was 230 GB, so allow 300 GB. Run nanoda after the comparator script, whose tools it reuses. Writing the 37.8 GB
  export takes about 90 GB of memory for an hour, and the check itself about 40 GB (about 30 minutes at 16 threads).
  Both scripts are for Linux (bash, git, python3, GNU coreutils; nanoda also needs `patch`, `cargo` and crates.io).

~~~sh
git clone <this repository> flt && cd flt
LEAN_NUM_THREADS=96 lake build              # one job per hardware thread by default; lower it to bound memory (about 5 GB per job)
verification/comparator/run.sh              # verdict: last line of .verify-work/wrapper/comparator.log
verification/nanoda/run.sh                  # after the comparator script; verdict: .verify-work/nanoda/run-*/nanoda.stdout
~~~

Lean prints a large number of deprecation and style-linter warnings while building. They do not affect the result.
The build has succeeded when its output ends with
`'flt_mathlib' depends on axioms: [propext, Classical.choice, Quot.sound]` and `Build completed successfully`. Each
script fetches and builds its checker at a pinned version and exits 0 on success.

## About the sources

`FinalCheck.lean` is the default target; `Theorems/` holds the statements, `P2M/Sol/` the proofs (each importing the
statements it cites), `Definitions/` the definitions, `verification/` the two checks, `html/` the web pages described
above and `tools/docs-site/` the program that generated them. The Lean sources were produced by AI agents building
on human-written open-source Lean, with Lean as the arbiter, and are written to be checked rather than read: names are
machine-generated, labels such as `P2M` or hexadecimal suffixes are pipeline labels rather than mathematics, and where
a name and a statement disagree the statement is what was proved. Comments were removed, apart from upstream notices,
doc strings and citations (listed in `ATTRIBUTION.md`) and the expected-output comment that `#guard_msgs` checks.

## Licence and attribution

Copyright 2026 Anthropic, PBC; released under the Apache License 2.0 (`LICENSE`). Portions derive from three
Apache-2.0 projects credited in `NOTICE`: the
[Imperial College London FLT project](https://github.com/ImperialCollegeLondon/FLT) led by Kevin Buzzard (Frey
package, Galois representations, deformation theory, patching and more),
[flt-regular](https://github.com/leanprover-community/flt-regular) (Kummer's theorem) and Mathlib. `ATTRIBUTION.md`
lists the 106 files containing material from the first two, with upstream file, copyright holder and authors, and the
23 files that reproduce Mathlib text (the excerpts in `Definitions/Def_Compat_Mathlib430.lean` and twenty-two modules
that re-prove a Mathlib lemma in place). The web pages bundle KaTeX and Graphviz (compiled to WebAssembly) under their
own licences, listed in `html/assets/vendor/LICENSES.txt`. Lean and the packages in `lake-manifest.json` are fetched
at build time, not distributed here. If you recognise unattributed material, the omission is unintentional.
