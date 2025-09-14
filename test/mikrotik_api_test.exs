defmodule MikrotikApiTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "GET builds IPv4 URL and returns 200 with raw body when decode: false" do
    raw = "{\"architecture-name\":\"arm64\",\"cpu\":\"ARM64\"}"

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/system/resource"
      assert body == :undefined
      assert Enum.any?(headers, fn {k, _} -> to_string(k) == "authorization" end)
      {:ok, {200, [], raw}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, ^raw} =
             MikrotikApi.get(auth, "10.0.0.1", "/system/resource", decode: false, scheme: :http)
  end

  test "IPv6 target is bracketed (http)" do
    MikrotikApi.Transport.Mock.put(fn _method, url, _headers, _body, _opts ->
      assert to_string(url) =~ "http://[2001:db8::1]:80/rest/system/resource"
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, nil} = MikrotikApi.get(auth, "2001:db8::1", "/system/resource", scheme: :http)
  end

  test "non-2xx produces error" do
    MikrotikApi.Transport.Mock.put(fn _m, _u, _h, _b, _o ->
      {:ok, {404, [], "not found"}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:error, %MikrotikApi.Error{status: 404}} = MikrotikApi.get(auth, "10.0.0.1", "/x")
  end
end
