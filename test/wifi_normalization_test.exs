defmodule MikrotikApi.WifiNormalizationTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "wifi_ssid_list 500 normalizes to :wifi_ssid_unavailable" do
    MikrotikApi.Transport.Mock.put(fn _method, _url, _headers, _body, _opts ->
      {:ok, {500, [], ~s({"error":500,"message":"Internal Server Error"})}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:error, %MikrotikApi.Error{status: 500, reason: :wifi_ssid_unavailable}} =
             MikrotikApi.wifi_ssid_list(auth, "10.0.0.1", scheme: :http)
  end
end
