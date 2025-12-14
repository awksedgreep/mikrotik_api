defmodule MikrotikApi.WireguardHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "wireguard_interface_list GET /interface/wireguard" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireguard"
      {:ok, {200, [], ~s([{".id":"*1","name":"wg0"}])}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, [%{".id" => "*1", "name" => "wg0"} | _]} =
             MikrotikApi.wireguard_interface_list(auth, "10.0.0.1", scheme: :http)
  end

  test "wireguard_interface_add PUT /interface/wireguard" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :put
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireguard"

      assert Enum.any?(headers, fn {k, v} ->
               to_string(k) == "content-type" and to_string(v) == "application/json"
             end)

      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    attrs = %{"name" => "wg0", "listen-port" => "51820"}

    assert {:ok, nil} =
             MikrotikApi.wireguard_interface_add(auth, "10.0.0.1", attrs, scheme: :http)
  end

  test "wireguard_interface_update PATCH /interface/wireguard/{id}" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      assert method == :patch
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireguard/*1"
      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")

    attrs = %{"listen-port" => "51821"}

    assert {:ok, nil} =
             MikrotikApi.wireguard_interface_update(auth, "10.0.0.1", "*1", attrs, scheme: :http)
  end

  test "wireguard_interface_ensure creates when missing" do
    Process.put({__MODULE__, :wg_called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :wg_called}) do
        false ->
          Process.put({__MODULE__, :wg_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireguard"
          {:ok, {200, [], ~s([])}}

        _ ->
          assert method == :put
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireguard"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, %{name: "wg0"}} =
             MikrotikApi.wireguard_interface_ensure(
               auth,
               "10.0.0.1",
               "wg0",
               %{"listen-port" => "51820"},
               scheme: :http
             )
  end
end
