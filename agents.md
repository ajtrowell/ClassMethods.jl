# Agent Notes

- `.julia` and `.juliaup` reside in the repository root so Julia writes stay inside the workspace sandbox.
- Use `scripts/run-tests.sh` to execute the full test suite; it exports `JULIA_DEPOT_PATH` and `HOME` before invoking `Pkg.test()`.
- For ad-hoc Julia commands, call `scripts/run-julia.sh <args>` which applies the same environment setup before running `julia --project=.`.
- Running Julia directly without these helpers can fail with permission errors while attempting to touch config files outside the sandbox.
