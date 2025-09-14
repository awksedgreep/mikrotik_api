defmodule MikrotikApi.MultiTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "multi returns results in input order and runs concurrently" do
    # Simulate variable response times per IP
    ip_sleeps = %{"10.0.0.1" => 50, "10.0.0.2" => 30, "10.0.0.3" => 40}

    MikrotikApi.Transport.Mock.put(fn _method, url, _headers, _body, _opts ->
      ip =
        url
        |> to_string()
        |> String.split(["://", ":80"], trim: true)
        |> Enum.at(1)

      Process.sleep(Map.fetch!(ip_sleeps, ip))
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    ips = ["10.0.0.1", "10.0.0.2", "10.0.0.3"]

    # Sequential timing
    {dt_seq_us, seq_results} =
      :timer.tc(fn ->
        Enum.map(ips, fn ip ->
          MikrotikApi.get(auth, ip, "/system/resource", scheme: :http, decode: false)
        end)
      end)

    # Parallel timing
    {dt_par_us, par_results} =
      :timer.tc(fn ->
        MikrotikApi.multi(auth, ips, :get, "/system/resource", [scheme: :http, decode: false],
          max_concurrency: 3,
          timeout: 5_000
        )
      end)

    # Order preserved
    assert Enum.map(par_results, & &1.ip) == ips
    assert length(par_results) == length(seq_results)

    dt_seq = div(dt_seq_us, 1000)
    dt_par = div(dt_par_us, 1000)

    sum_sleep = Enum.reduce(ip_sleeps, 0, fn {_k, v}, acc -> acc + v end)
    max_sleep = Enum.max(Map.values(ip_sleeps))

    assert dt_seq >= sum_sleep - 5
    assert dt_par <= max_sleep + 15
  end
end
