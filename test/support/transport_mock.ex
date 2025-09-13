defmodule MikrotikApi.Transport.Mock do
  @behaviour MikrotikApi.Transport

  @moduledoc false

  # Simple function-based mock; set expectations in the test process via put/1.

  def put(fun) when is_function(fun, 5) do
    Process.put({__MODULE__, :fun}, fun)
    :ok
  end

  @impl true
  def request(method, url, headers, body, opts) do
    fun = Process.get({__MODULE__, :fun}) || raise "Mock not configured"
    fun.(method, url, headers, body, opts)
  end
end
