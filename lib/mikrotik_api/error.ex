defmodule MikrotikApi.Error do
  @moduledoc """
  Error struct returned by MikrotikApi functions.

  ## Fields

  - `status` - HTTP status code (integer) or `nil` for transport errors
  - `reason` - Atom or string describing the error type (e.g., `:http_error`, `:transport_error`)
  - `details` - Additional error details (response body, error message, etc.)
  """
  defstruct status: nil, reason: nil, details: nil

  @type t :: %__MODULE__{
          status: integer() | nil,
          reason: atom() | String.t(),
          details: term()
        }
end
