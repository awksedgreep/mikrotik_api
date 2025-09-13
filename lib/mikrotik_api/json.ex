defmodule MikrotikApi.JSON do
  @moduledoc false

  # Minimal stubs to be replaced by internal JSON codec
  # Implement encode!/1 and decode/1 as needed.

  def encode!(term) do
    raise "JSON.encode!/1 not implemented (internal JSON module stub)"
  end

  def decode(binary) when is_binary(binary) do
    raise "JSON.decode/1 not implemented (internal JSON module stub)"
  end
end
