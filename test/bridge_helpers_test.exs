defmodule MikrotikApi.BridgeHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "bridge_list GET /interface/bridge" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge"
      {:ok, {200, [], ~s([{".id":"*1","name":"bridge"}])}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, [%{".id" => "*1", "name" => "bridge"} | _]} =
             MikrotikApi.bridge_list(auth, "10.0.0.1", scheme: :http)
  end

  test "bridge_port_add POST /interface/bridge/port" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :post
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/port"

      assert Enum.any?(headers, fn {k, v} ->
               to_string(k) == "content-type" and to_string(v) == "application/json"
             end)

      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    attrs = %{"bridge" => "bridge", "interface" => "ether2"}
    assert {:ok, nil} = MikrotikApi.bridge_port_add(auth, "10.0.0.1", attrs, scheme: :http)
  end

  test "bridge_vlan_update PATCH /interface/bridge/vlan/{id}" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :patch
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/vlan/*1"
      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")

    attrs = %{
      "vlan-ids" => "10",
      "bridge" => "bridge",
      "tagged" => "sfp-sfpplus1,ether1",
      "untagged" => "ether2"
    }

    assert {:ok, nil} =
             MikrotikApi.bridge_vlan_update(auth, "10.0.0.1", "*1", attrs, scheme: :http)
  end

  test "bridge_vlan_ensure creates when missing" do
    Process.put({__MODULE__, :vlan_called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :vlan_called}) do
        false ->
          Process.put({__MODULE__, :vlan_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/vlan"
          {:ok, {200, [], ~s([])}}

        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/bridge/vlan"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, {"bridge", "10"}} =
             MikrotikApi.bridge_vlan_ensure(
               auth,
               "10.0.0.1",
               "bridge",
               "10",
               %{"tagged" => "ether1"},
               scheme: :http
             )
  end
end
