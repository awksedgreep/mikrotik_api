defmodule MikrotikApi.Phase1HelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "system_health delegates to GET /system/health" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/system/health"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "{}"} = MikrotikApi.system_health(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "system_packages delegates to GET /system/package" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/system/package"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.system_packages(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "firewall_connection_list delegates to GET /ip/firewall/connection" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/connection"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.firewall_connection_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "dns_config delegates to GET /ip/dns" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/dns"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "{}"} = MikrotikApi.dns_config(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "dns_cache_list delegates to GET /ip/dns/cache" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/dns/cache"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.dns_cache_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ip_pool_list delegates to GET /ip/pool" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/pool"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "[]"} = MikrotikApi.ip_pool_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "firewall_address_list delegates to GET /ip/firewall/address-list" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/address-list"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.firewall_address_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end
end
