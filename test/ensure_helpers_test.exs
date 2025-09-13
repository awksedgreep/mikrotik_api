defmodule MikrotikApi.EnsureHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "ip_address_ensure creates when missing" do
    Process.put({__MODULE__, :ip_called}, false)
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :ip_called}) do
        false ->
          Process.put({__MODULE__, :ip_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/address"
          {:ok, {200, [], ~s([])}}
        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/address"
          assert Enum.any?(headers, fn {k, v} -> to_string(k) == "content-type" and to_string(v) == "application/json" end)
          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")
    attrs = %{"address" => "192.168.88.2/24", "interface" => "bridge"}
    assert {:ok, "192.168.88.2/24"} = MikrotikApi.ip_address_ensure(auth, "10.0.0.1", attrs, scheme: :http)
  end

  test "firewall_filter_ensure matches existing by chain+action" do
    body = ~s([{".id":"*1","chain":"forward","action":"accept"}])
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")
    rule = %{"chain" => "forward", "action" => "accept", "comment" => "allow"}
    assert {:ok, %{"chain" => "forward", "action" => "accept"}} =
             MikrotikApi.firewall_filter_ensure(auth, "10.0.0.1", rule, scheme: :http)
  end

  test "firewall_filter_ensure creates when missing with custom keys" do
    Process.put({__MODULE__, :fw_called}, false)
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :fw_called}) do
        false ->
          Process.put({__MODULE__, :fw_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter"
          {:ok, {200, [], ~s([])}}
        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter"
          assert Enum.any?(headers, fn {k, v} -> to_string(k) == "content-type" and to_string(v) == "application/json" end)
          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")
    rule = %{"chain" => "forward", "action" => "drop", "src-address" => "10.0.0.0/8"}
    assert {:ok, %{"chain" => "forward", "src-address" => "10.0.0.0/8"}} =
             MikrotikApi.firewall_filter_ensure(auth, "10.0.0.1", rule, unique_keys: ["chain", "src-address"], scheme: :http)
  end
end
