defmodule MikrotikApi.Error do
  @moduledoc false
  defstruct status: nil, reason: nil, details: nil

  @type t :: %__MODULE__{
          status: integer() | nil,
          reason: atom() | String.t(),
          details: term()
        }
end