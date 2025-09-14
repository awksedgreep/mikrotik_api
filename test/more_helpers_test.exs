defmodule MikrotikApi.MoreHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "interface_enable sets disabled=false via PATCH /interface/{id}" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :patch
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/ether1"
      # body is charlist JSON
      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, nil} = MikrotikApi.interface_enable(auth, "10.0.0.1", "ether1", scheme: :http)
  end

  test "dhcp_lease_list GET /ip/dhcp-server/lease" do
    body = ~s([{".id":"*1","address":"192.168.88.100","mac-address":"AA:BB:CC:DD:EE:FF"}])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/dhcp-server/lease"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, [%{".id" => "*1", "address" => _} | _]} =
             MikrotikApi.dhcp_lease_list(auth, "10.0.0.1", scheme: :http)
  end

  test "route_add POST /ip/route" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :post
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/route"

      assert Enum.any?(headers, fn {k, v} ->
               to_string(k) == "content-type" and to_string(v) == "application/json"
             end)

      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    attrs = %{"dst-address" => "10.10.0.0/16", "gateway" => "192.168.88.1"}
    assert {:ok, nil} = MikrotikApi.route_add(auth, "10.0.0.1", attrs, scheme: :http)
  end
end
