defmodule MikrotikApi.WireguardPairWorkflowTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "ensure_wireguard_pair succeeds when A exposes private-key" do
    # Sequence of calls we expect:
    # 1) GET A /interface/wireguard -> empty -> 2) POST A create
    # 3) GET A /interface/wireguard -> returns entry with private-key
    # 4) GET B /interface/wireguard -> empty -> 5) POST/PATCH B with same key

    Process.put({__MODULE__, :state}, :first_get_a)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      state = Process.get({__MODULE__, :state})
      path =
        url
        |> to_string()
        |> String.replace(~r/^http:\/\/(\[.*\]|[^\/]+):80\/rest\//, "")

      case {state, method, path} do
        {:first_get_a, :get, "interface/wireguard"} ->
          Process.put({__MODULE__, :state}, :post_a)
          {:ok, {200, [], ~s([])}}

        {:post_a, :post, "interface/wireguard"} ->
          # Creation on A
          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)
          assert is_list(body)
          Process.put({__MODULE__, :state}, :second_get_a)
          {:ok, {200, [], ""}}

        {:second_get_a, :get, "interface/wireguard"} ->
          # Return entry with private-key on A
          body = ~s([{".id":"*A1","name":"wgA","private-key":"K+BASE64+KEY"}])
          Process.put({__MODULE__, :state}, :first_get_b)
          {:ok, {200, [], body}}

        {:first_get_b, :get, "interface/wireguard"} ->
          Process.put({__MODULE__, :state}, :post_b)
          {:ok, {200, [], ~s([])}}

        {:post_b, :post, "interface/wireguard"} ->
          # Ensure B contains the same private-key in payload; body is charlist
          assert is_list(body)
          json = to_string(body)
          assert String.contains?(json, "\"private-key\":\"K+BASE64+KEY\"")
          {:ok, {200, [], ""}}

        other ->
          flunk("unexpected call: #{inspect(other)} with url=#{to_string(url)}")
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    attrs = %{"listen-port" => "51820"}

    assert {:ok, %{a: %{name: "wgA"}, b: %{name: "wgB"}}} =
             MikrotikApi.ensure_wireguard_pair(
               auth,
               "10.0.0.1",
               "wgA",
               "10.0.0.2",
               "wgB",
               attrs,
               scheme: :http
             )
  end

  test "ensure_wireguard_pair errors when A private-key not exposed" do
    Process.put({__MODULE__, :state}, :initial_get_a)

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, body, _opts ->
      state = Process.get({__MODULE__, :state})
      path =
        url
        |> to_string()
        |> String.replace(~r/^http:\/\/(\[.*\]|[^\/]+):80\/rest\//, "")

      case {state, method, path} do
        {:initial_get_a, :get, "interface/wireguard"} ->
          # Return entry without private-key on A
          Process.put({__MODULE__, :state}, :patch_a)
          {:ok, {200, [], ~s([{".id":"*A1","name":"wgA"}])}}

        {:patch_a, :patch, "interface/wireguard/*A1"} ->
          # Handle the patch call that was causing the error
          Process.put({__MODULE__, :state}, :get_b_interface)
          {:ok, {200, [], ""}}

        {:get_b_interface, :get, "interface/wireguard"} ->
          Process.put({__MODULE__, :state}, :post_b_interface)
          {:ok, {200, [], ~s([])}}

        {:post_b_interface, :post, "interface/wireguard"} ->
          assert is_list(body)
          Process.put({__MODULE__, :state}, :done)
          {:ok, {200, [], ""}}

        other ->
          flunk("unexpected call: #{inspect(other)}")
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:error, %MikrotikApi.Error{reason: :wireguard_private_key_unreadable}} =
             MikrotikApi.ensure_wireguard_pair(
               auth,
               "10.0.0.1",
               "wgA",
               "10.0.0.2",
               "wgB",
               %{"listen-port" => "51820"},
               scheme: :http
             )
  end
end
