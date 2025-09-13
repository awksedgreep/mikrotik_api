# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Project overview and architecture
- Purpose: Elixir wrapper for MikroTik RouterOS REST API focused on a simple, stateless Client you pass into each call. Prefer programmatic POST for create/command-style operations while supporting standard REST verbs.
- Client: Construct a Client with connection/auth options (scheme, host, username, password, verify). Pass this Client to functions such as get/2 and post/3. Functions return {:ok, data} | {:error, reason} and must use Logger for all output (no IO.puts/IO.inspect).
- Transport and JSON: The README illustrates Req (HTTP) and Jason (JSON). mix.exs does not yet include these deps; add them when implementing network calls.
- Security posture: Prefer HTTPS with certificate verification (:verify_peer). Allow :verify_none only for lab setups where you accept the risk.
- Planning docs: rest_api.md is present and is the authoritative spec/plan. Consult it first for dependency choices (Req/Jason), Client struct fields, core function surface (get/post/put/patch/delete and helpers), error model, logging policy, TLS guidance, and testing approach.

Common development commands
- Setup and build
  - mix deps.get
  - mix compile
  - Elixir version: ~> 1.18 (from mix.exs)
- Formatting
  - mix format
  - mix format --check-formatted
- Tests (ExUnit)
  - mix test
  - Run a single test by file and line: mix test test/path/to_test.exs:LINE
- REPL with project loaded
  - iex -S mix

Repository-specific rules and notes
- Logging: Do not use IO.puts/IO.inspect. Use Logger.xxx for all logging and redact credentials in messages.
- Agent rules: If an AGENTS.md is added to this repo, follow it exactly.
- Linting: No linter is configured in this repo. If you add Credo later, update this file with the exact commands.
- Files observed: mix.exs, README.md, .formatter.exs, and rest_api.md. Library modules and tests will live under lib/ and test/ respectively (both present but currently untracked/empty).

Key references
- MikroTik RouterOS REST API: https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API
- README.md in this repo includes a Quick Start snippet demonstrating Client creation and GET/POST usage and reiterates security guidance.
