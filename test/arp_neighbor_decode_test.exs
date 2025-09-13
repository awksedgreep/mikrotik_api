defmodule MikrotikApi.ArpNeighborDecodeTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "interface_list decodes array of interfaces" do
    body = ~s([
      {".id":"*1","name":"ether1","type":"ether","running":"false"},
      {".id":"*A","name":"bridgeLocal","type":"bridge","running":"true"}
    ])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, list} = MikrotikApi.interface_list(auth, "10.0.0.1", scheme: :http)
    assert length(list) == 2
    assert Enum.any?(list, &(&1["type"] == "bridge"))
  end

  test "arp_list decodes entries with address and mac-address" do
    body = ~s([
      {".id":"*1","address":"192.168.89.1","mac-address":"F4:1E:57:2D:A8:92","interface":"sfp-sfpplus1","status":"reachable"}
    ])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/arp"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, [entry]} = MikrotikApi.arp_list(auth, "10.0.0.1", scheme: :http)
    assert entry["address"] == "192.168.89.1"
    assert entry["mac-address"]
  end

  test "neighbor_list decodes entries with identity and board info" do
    body = ~s([
      {".id":"*3","address":"192.168.89.1","identity":"MikroTikAx3","board":"C53UiG+5HPaxD2HPaxD","platform":"MikroTik"}
    ])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/neighbor"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, [entry]} = MikrotikApi.neighbor_list(auth, "10.0.0.1", scheme: :http)
    assert entry["identity"] == "MikroTikAx3"
    assert entry["platform"] == "MikroTik"
  end
end