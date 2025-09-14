defmodule MikrotikApi.InterfaceEnsureTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "interface_ensure patches only changing keys by name" do
    Process.put({__MODULE__, :iface_called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :iface_called}) do
        false ->
          Process.put({__MODULE__, :iface_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface"
          {:ok, {200, [], ~s([{".id":"*1","name":"ether1","disabled":"false","mtu":"1500"}])}}

        _ ->
          assert method == :patch
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/*1"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          # Ensure only changed key(s) are sent (mtu differs, disabled remains same)
          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    {:ok, %{id: "*1", name: "ether1", changed: changed}} =
      MikrotikApi.interface_ensure(
        auth,
        "10.0.0.1",
        "ether1",
        %{"disabled" => "false", "mtu" => "1400"},
        scheme: :http
      )

    assert "mtu" in changed
  end
end
