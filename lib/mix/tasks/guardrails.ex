defmodule Mix.Tasks.Guardrails do
  use Mix.Task
  require Logger

  @shortdoc "Scan for disallowed patterns (IO.puts/IO.inspect, legacy JSON module)"
  @moduledoc """
  Scans source files for disallowed patterns and fails if any are found.

  Disallowed patterns:
  - IO.puts
  - IO.inspect
  - MikrotikApi.JSON (legacy proprietary JSON module)

  Usage:
    mix guardrails
  """

  @impl true
  def run(_args) do
    files =
      globs()
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.reject(&skip?/1)

    patterns = patterns()

    findings =
      files
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, bin} ->
            for {regex, label} <- patterns, Regex.match?(regex, bin), do: {file, label}

          {:error, _} ->
            []
        end
      end)

    if findings == [] do
      Logger.info("guardrails: OK (no disallowed patterns found)")
    else
      Enum.each(findings, fn {file, label} ->
        Logger.error("guardrails: disallowed pattern #{label} in #{file}")
      end)

      Mix.raise("guardrails failed: disallowed patterns present")
    end
  end

  defp globs do
    ["lib/**/*.ex", "test/**/*.exs", "config/**/*.exs", "mix.exs"]
  end

  defp patterns do
    [
      {Regex.compile!("\\bIO\\.puts\\b"), "IO.puts"},
      {Regex.compile!("\\bIO\\.inspect\\b"), "IO.inspect"},
      {Regex.compile!("\\bMikrotikApi\\.JSON\\b"), "MikrotikApi.JSON"}
    ]
  end

  defp skip?(file) do
    String.ends_with?(file, "lib/mix/tasks/guardrails.ex")
  end
end
