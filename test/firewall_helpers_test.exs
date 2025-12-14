defmodule MikrotikApi.FirewallHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "firewall_filter_list delegates to GET /ip/firewall/filter (http) and decodes" do
    body = ~s([{".id":"*1","chain":"forward","action":"accept"}])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, [%{".id" => "*1", "chain" => "forward", "action" => "accept"}]} =
             MikrotikApi.firewall_filter_list(auth, "10.0.0.1", scheme: :http)
  end

  test "firewall_filter_add posts JSON to /ip/firewall/filter and returns raw body with decode: false" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :put
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter"

      assert Enum.any?(headers, fn {k, v} ->
               to_string(k) == "content-type" and to_string(v) == "application/json"
             end)

      assert is_list(body)
      {:ok, {200, [], "{\"ok\":true}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    rule = %{"chain" => "forward", "action" => "accept"}

    assert {:ok, "{\"ok\":true}"} =
             MikrotikApi.firewall_filter_add(auth, "10.0.0.1", rule, scheme: :http, decode: false)
  end

  test "firewall_filter_delete calls DELETE /ip/firewall/filter/{id}" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :delete
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/firewall/filter/*1"
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, nil} = MikrotikApi.firewall_filter_delete(auth, "10.0.0.1", "*1", scheme: :http)
  end
end
