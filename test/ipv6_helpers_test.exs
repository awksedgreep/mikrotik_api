defmodule MikrotikApi.IPv6HelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "ipv6_route_list delegates to GET /ipv6/route" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ipv6/route"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ipv6_route_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ipv6_pool_list delegates to GET /ipv6/pool" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ipv6/pool"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ipv6_pool_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ipv6_firewall_filter_list delegates to GET /ipv6/firewall/filter" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ipv6/firewall/filter"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ipv6_firewall_filter_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ipv6_neighbor_list delegates to GET /ipv6/neighbor" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ipv6/neighbor"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ipv6_neighbor_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ipv6_firewall_address_list delegates to GET /ipv6/firewall/address-list" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ipv6/firewall/address-list"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ipv6_firewall_address_list(auth, "10.0.0.1",
               decode: false,
               scheme: :http
             )
  end
end
