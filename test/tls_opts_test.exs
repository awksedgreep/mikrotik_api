defmodule MikrotikApi.TLSOptsTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "verify_peer auto-injects cacerts when none provided" do
    MikrotikApi.Transport.Mock.put(fn _method, _url, _headers, _body, opts ->
      http_opts = Keyword.fetch!(opts, :http_opts)
      ssl = Keyword.fetch!(http_opts, :ssl)
      assert Keyword.get(ssl, :verify) == :verify_peer
      assert Keyword.has_key?(ssl, :cacerts)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p", verify: :verify_peer, ssl_opts: [])
    assert {:ok, nil} = MikrotikApi.get(auth, "10.0.0.1", "/system/resource", scheme: :https)
  end

  test "verify_peer respects user cacertfile" do
    MikrotikApi.Transport.Mock.put(fn _method, _url, _headers, _body, opts ->
      http_opts = Keyword.fetch!(opts, :http_opts)
      ssl = Keyword.fetch!(http_opts, :ssl)
      assert Keyword.get(ssl, :verify) == :verify_peer
      refute Keyword.has_key?(ssl, :cacerts)
      assert Keyword.get(ssl, :cacertfile) == "/tmp/ca.pem"
      {:ok, {200, [], ""}}
    end)

    auth =
      Auth.new(
        username: "u",
        password: "p",
        verify: :verify_peer,
        ssl_opts: [cacertfile: "/tmp/ca.pem"]
      )

    assert {:ok, nil} = MikrotikApi.get(auth, "10.0.0.1", "/system/resource", scheme: :https)
  end

  test "verify_none disables peer verification" do
    MikrotikApi.Transport.Mock.put(fn _method, _url, _headers, _body, opts ->
      http_opts = Keyword.fetch!(opts, :http_opts)
      ssl = Keyword.fetch!(http_opts, :ssl)
      assert Keyword.get(ssl, :verify) == :verify_none
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p", verify: :verify_none, ssl_opts: [])
    assert {:ok, nil} = MikrotikApi.get(auth, "10.0.0.1", "/system/resource", scheme: :https)
  end
end
