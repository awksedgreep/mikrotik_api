defmodule MikrotikApi.FirewallNatEnsureTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "firewall_nat_ensure creates when missing" do
    Process.put({__MODULE__, :nat_called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :nat_called}) do
        false ->
          Process.put({__MODULE__, :nat_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/nat"
          {:ok, {200, [], ~s([])}}

        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/nat"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")
    rule = %{"chain" => "dstnat", "action" => "dst-nat", "to-addresses" => "192.168.88.2"}

    assert {:ok, %{"chain" => "dstnat", "action" => "dst-nat"}} =
             MikrotikApi.firewall_nat_ensure(auth, "10.0.0.1", rule, scheme: :http)
  end
end
