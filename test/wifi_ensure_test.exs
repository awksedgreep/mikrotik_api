defmodule MikrotikApi.WifiEnsureTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "wifi_security_ensure returns existing name" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wifi/security"
      {:ok, {200, [], ~s([{"name":"SEC1"}])}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "SEC1"} =
             MikrotikApi.wifi_security_ensure(auth, "10.0.0.1", "SEC1", %{}, scheme: :http)
  end

  test "wifi_ssid_ensure creates when missing" do
    Process.put({__MODULE__, :ssid_called}, false)

    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      case Process.get({__MODULE__, :ssid_called}) do
        false ->
          Process.put({__MODULE__, :ssid_called}, true)
          assert method == :get
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/wifi/ssid"
          {:ok, {200, [], ~s([])}}

        _ ->
          assert method == :post
          assert to_string(url) == "http://10.0.0.1:80/rest/interface/wifi/ssid"

          assert Enum.any?(headers, fn {k, v} ->
                   to_string(k) == "content-type" and to_string(v) == "application/json"
                 end)

          assert is_list(body)
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, "SSID1"} =
             MikrotikApi.wifi_ssid_ensure(auth, "10.0.0.1", "SSID1", %{"security" => "SEC1"},
               scheme: :http
             )
  end
end
