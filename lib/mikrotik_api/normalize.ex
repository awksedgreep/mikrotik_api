defmodule MikrotikApi.Normalize do
  @moduledoc """
  Optional normalization helpers for turning RouterOS string fields into typed values.

  NOTE: Core helpers do not depend on this module. Exporters may choose to use
  these utilities when building metrics.
  """

  @doc """
  Convert common string booleans to true/false.
  Accepts: true/false, "true"/"false", "yes"/"no", "enabled"/"disabled".
  Returns boolean or the original value if not matched.
  """
  @spec normalize_bool(term()) :: boolean() | term()
  def normalize_bool(true), do: true
  def normalize_bool(false), do: false

  def normalize_bool(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "true" -> true
      "false" -> false
      "yes" -> true
      "no" -> false
      "enabled" -> true
      "disabled" -> false
      _ -> v
    end
  end

  def normalize_bool(v), do: v

  @doc """
  Convert numeric-looking strings (e.g., "-64", "1500") to integers.
  Returns integer or original value if parsing fails.
  """
  @spec to_int(term()) :: integer() | term()
  def to_int(v) when is_integer(v), do: v

  def to_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, ""} -> i
      _ -> v
    end
  end

  def to_int(v), do: v

  @doc """
  Convert float-looking strings (e.g., "-3.14", "1.0e3") to floats.
  Returns float or original value if parsing fails.
  """
  @spec to_float(term()) :: float() | term()
  def to_float(v) when is_float(v), do: v

  def to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, rest} when rest in ["", "e0", "E0"] -> f
      _ -> v
    end
  end

  def to_float(v), do: v

  @doc """
  Parse rates like "877 Mbps" or "54 Mbps" into integer Mbps.
  Returns integer Mbps or original value if the unit doesn't match.
  """
  @spec parse_rate_mbps(term()) :: integer() | term()
  def parse_rate_mbps(v) when is_binary(v) do
    sd = v |> String.trim() |> String.downcase()

    if String.ends_with?(sd, " mbps") do
      prefix = binary_part(sd, 0, byte_size(sd) - byte_size(" mbps"))

      case Integer.parse(String.trim(prefix)) do
        {i, ""} -> i
        _ -> v
      end
    else
      v
    end
  end

  def parse_rate_mbps(v), do: v
end
