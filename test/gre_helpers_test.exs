defmodule MikrotikApi.GreHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "gre_list GET /interface/gre" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/gre"
      {:ok, {200, [], ~s([{".id":"*5","name":"gre-wan"}])}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, [%{".id" => "*5", "name" => "gre-wan"} | _]} =
             MikrotikApi.gre_list(auth, "10.0.0.1", scheme: :http)
  end

  test "gre_ensure creates when missing" do
    Process.put({__MODULE__, :called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :called}) do
        false ->
          Process.put({__MODULE__, :called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/gre"
          {:ok, {200, [], ~s([])}}

        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/gre"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, %{name: "gre-wan"}} =
             MikrotikApi.gre_ensure(
               auth,
               "10.0.0.1",
               "gre-wan",
               %{"local-address" => "192.0.2.10", "remote-address" => "198.51.100.20"},
               scheme: :http
             )
  end

  test "gre_ensure patches only diffs when existing" do
    # First GET returns an existing gre with mtu 1476; we request mtu 1400 so it should PATCH only mtu.
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      case {method, to_string(url)} do
        {:get, "http://10.0.0.1:80/rest/interface/gre"} ->
          {:ok,
           {200, [],
            ~s([{".id":"*5","name":"gre-wan","mtu":"1476","local-address":"192.0.2.10","remote-address":"198.51.100.20"}])}}

        {:patch, "http://10.0.0.1:80/rest/interface/gre/*5"} ->
          # body is an iolist (charlist) containing JSON
          json = IO.iodata_to_binary(body)
          # Should contain only mtu change
          assert String.contains?(json, "\"mtu\":\"1400\"")
          refute String.contains?(json, "local-address")
          refute String.contains?(json, "remote-address")
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, %{id: "*5", name: "gre-wan", changed: ["mtu"]}} =
             MikrotikApi.gre_ensure(
               auth,
               "10.0.0.1",
               "gre-wan",
               %{
                 "mtu" => "1400",
                 "local-address" => "192.0.2.10",
                 "remote-address" => "198.51.100.20"
               },
               scheme: :http
             )
  end

  test "gre_add falls back to /interface/gre/add on 'no such command'" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case {method, to_string(url)} do
        {:post, "http://10.0.0.1:80/rest/interface/gre"} ->
          {:ok, {400, [], "no such command"}}

        {:post, "http://10.0.0.1:80/rest/interface/gre/add"} ->
          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    attrs = %{
      "name" => "gre-wan",
      "local-address" => "192.0.2.10",
      "remote-address" => "198.51.100.20"
    }

    assert {:ok, nil} = MikrotikApi.gre_add(auth, "10.0.0.1", attrs, scheme: :http)
  end
end
