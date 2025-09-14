defmodule MikrotikApi.Auth do
  @moduledoc """
  Authentication and request policy used per call alongside a target IP.

  Construct once (credentials, TLS verification, timeouts, retry policy), then
  pass with a target IP to each API call.
  """

  @enforce_keys [:username, :password]
  defstruct username: nil,
            password: nil,
            verify: :verify_peer,
            recv_timeout: 15_000,
            connect_timeout: 5_000,
            retry: %{max_attempts: 2, backoff_ms: 250},
            default_headers: [],
            ssl_opts: []

  @type t :: %__MODULE__{
          username: String.t(),
          password: String.t(),
          verify: :verify_peer | :verify_none,
          recv_timeout: non_neg_integer(),
          connect_timeout: non_neg_integer(),
          retry: %{max_attempts: non_neg_integer(), backoff_ms: non_neg_integer()},
          default_headers: [{binary(), binary()}],
          ssl_opts: keyword()
        }

  @doc """
  Build an Auth struct.

  Options:
  - :username, :password (required)
  - :verify (:verify_peer | :verify_none) default :verify_peer
  - :recv_timeout (ms) default 15_000
  - :connect_timeout (ms) default 5_000
  - :retry (%{max_attempts, backoff_ms}) default %{max_attempts: 2, backoff_ms: 250}
  - :default_headers list of {key, value} binaries
  - :ssl_opts keyword passed to :ssl (e.g., cacerts, cacertfile, server_name_indication)
  """
  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)

    %__MODULE__{
      username: username,
      password: password,
      verify: Keyword.get(opts, :verify, :verify_peer),
      recv_timeout: Keyword.get(opts, :recv_timeout, 15_000),
      connect_timeout: Keyword.get(opts, :connect_timeout, 5_000),
      retry: Keyword.get(opts, :retry, %{max_attempts: 2, backoff_ms: 250}),
      default_headers: Keyword.get(opts, :default_headers, []),
      ssl_opts: Keyword.get(opts, :ssl_opts, [])
    }
  end
end
