defmodule MikrotikApi.ResourceHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "system_resource delegates to GET /system/resource (http)" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/system/resource"
      assert body == :undefined
      {:ok, {200, [], "{}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, "{}"} = MikrotikApi.system_resource(auth, "10.0.0.1", decode: false, scheme: :http)
  end

  test "ip_address_add posts JSON body to /ip/address" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :post
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/address"
      # content-type header
      assert Enum.any?(headers, fn {k, v} -> to_string(k) == "content-type" and to_string(v) == "application/json" end)
      assert is_list(body)
      {:ok, {200, [], "{\"ok\":true}"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    attrs = %{"address" => "192.168.88.2/24", "interface" => "bridge"}
    assert {:ok, "{\"ok\":true}"} = MikrotikApi.ip_address_add(auth, "10.0.0.1", attrs, decode: false, scheme: :http)
  end
end
