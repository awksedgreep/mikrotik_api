defmodule MikrotikApi.Transport.Mock do
  @behaviour MikrotikApi.Transport

  @moduledoc false

  # Function-based transport mock that isolates expectations per test process.
  # Expectations are stored under the calling process PID; concurrent tasks can
  # be associated with the test owner via opts[:owner_pid].

  def put(fun) when is_function(fun, 5) do
    :persistent_term.put({__MODULE__, :fun, self()}, fun)
    :ok
  end

  @impl true
  def request(method, url, headers, body, opts) do
    owner = Keyword.get(opts, :owner_pid, self())
    key = {__MODULE__, :fun, owner}
    fun = :persistent_term.get(key, nil)

    unless is_function(fun, 5) do
      raise "Mock not configured for owner_pid=#{inspect(owner)}"
    end

    fun.(method, url, headers, body, opts)
  end
end
