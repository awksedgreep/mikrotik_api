defmodule MikrotikApi.BridgePortEnsureTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "bridge_port_ensure creates when missing" do
    Process.put({__MODULE__, :bp_called}, false)
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :bp_called}) do
        false ->
          Process.put({__MODULE__, :bp_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/port"
          {:ok, {200, [], ~s([])}}
        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/port"
          assert Enum.any?(headers, fn {k, v} -> to_string(k) == "content-type" and to_string(v) == "application/json" end)
          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, {"bridge", "ether2"}} = MikrotikApi.bridge_port_ensure(auth, "10.0.0.1", "bridge", "ether2", %{}, scheme: :http)
  end
end
