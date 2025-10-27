# Agent usage

This repo is provisioned to vendor a local Julia depot per project.

## Running Julia from an agent

Use `scripts/agent/run-julia.sh` as the entrypoint instead of calling `julia` directly. It sets `JULIA_DEPOT_PATH=./.julia`, resolves the vendored Julia binary under `./.julia/juliaup/…/bin/julia`, and runs with `--project=.` automatically so no Juliaup refresh is required (requires `python3` in PATH).

Examples:

- Run a file:
  scripts/agent/run-julia.sh myscript.jl

- Eval a snippet:
  scripts/agent/run-julia.sh -e 'using JSON3; println(JSON3.write((a=1,)))'

- Run tests:
  scripts/agent/run-tests.sh
