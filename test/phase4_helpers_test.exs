defmodule MikrotikApi.Phase4HelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "ethernet_poe_list delegates to GET /interface/ethernet/poe" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/ethernet/poe"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ethernet_poe_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "interface_ethernet_monitor delegates to GET /interface/ethernet/monitor/{ident}" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/ethernet/monitor/ether1"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "{}"} =
             MikrotikApi.interface_ethernet_monitor(auth, "10.0.0.1", "ether1",
               decode: false,
               scheme: :http
             )
  end

  test "tool_netwatch_list delegates to GET /tool/netwatch" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/tool/netwatch"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.tool_netwatch_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ip_cloud_info delegates to GET /ip/cloud" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/cloud"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "{}"} = MikrotikApi.ip_cloud_info(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "eoip_list delegates to GET /interface/eoip" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/eoip"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "[]"} = MikrotikApi.eoip_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "gre_list delegates to GET /interface/gre" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/gre"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "[]"} = MikrotikApi.gre_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ipip_list delegates to GET /interface/ipip" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/ipip"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "[]"} = MikrotikApi.ipip_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ethernet_switch_port_list delegates to GET /interface/ethernet/switch/port" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/ethernet/switch/port"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.ethernet_switch_port_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "user_active_list delegates to GET /user/active" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/user/active"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.user_active_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "queue_simple_list delegates to GET /queue/simple" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/queue/simple"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.queue_simple_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "queue_tree_list delegates to GET /queue/tree" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/queue/tree"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.queue_tree_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "routing_bfd_list delegates to GET /routing/bfd/session" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/routing/bfd/session"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.routing_bfd_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "routing_bgp_list delegates to GET /routing/bgp/session" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/routing/bgp/session"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.routing_bgp_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "routing_stats delegates to GET /routing/stats" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/routing/stats"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "{}"} = MikrotikApi.routing_stats(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "certificate_list delegates to GET /certificate" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/certificate"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.certificate_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "container_list delegates to GET /container" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/container"
      assert body == :undefined
      {:ok, {200, [], "[]"}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "[]"} =
             MikrotikApi.container_list(auth, "10.0.0.1", decode: false, scheme: :http)
  end
end
