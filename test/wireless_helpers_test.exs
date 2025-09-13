defmodule MikrotikApi.WirelessHelpersTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "wireless_interface_list GET /interface/wireless (http)" do
    body = ~s([{".id":"*1","name":"wlan1","disabled":"false"}])

    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      assert method == :get
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wireless"
      {:ok, {200, [], body}}
    end)

    auth = Auth.new(username: "u", password: "p")
    assert {:ok, [%{"name" => "wlan1"} | _]} =
             MikrotikApi.wireless_interface_list(auth, "10.0.0.1", scheme: :http)
  end

  test "wifi_ssid_add POST /interface/wifi/ssid (http)" do
    MikrotikApi.Transport.Mock.put(fn method, url, headers, body, _opts ->
      assert method == :post
      assert to_string(url) == "http://10.0.0.1:80/rest/interface/wifi/ssid"
      assert Enum.any?(headers, fn {k, v} -> to_string(k) == "content-type" and to_string(v) == "application/json" end)
      assert is_list(body)
      {:ok, {200, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")
    ssid = %{"name" => "WG-LAB", "security" => "wpa2"}
    assert {:ok, nil} = MikrotikApi.wifi_ssid_add(auth, "10.0.0.1", ssid, scheme: :http)
  end
end