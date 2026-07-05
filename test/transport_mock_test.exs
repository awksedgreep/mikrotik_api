defmodule MikrotikApi.TransportMockTest do
  use ExUnit.Case, async: true

  alias MikrotikApi.Auth
  alias MikrotikApi.Transport.Mock

  setup do
    Application.put_env(:mikrotik_api, :transport, Mock)
    Mock.clear()
    :ok
  end

  test "stubs RouterOS endpoint responses" do
    Mock.stub(:get, "/system/resource", 200, %{"uptime" => "1h", "board-name" => "hAP ax2"})

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, %{"uptime" => "1h", "board-name" => "hAP ax2"}} =
             MikrotikApi.system_resource(auth, "10.0.0.1", scheme: :http)
  end

  test "low-level handler can assert request details" do
    Mock.put(fn method, url, headers, body, _opts ->
      assert method == :put
      assert to_string(url) == "http://10.0.0.1:80/rest/ip/address"
      assert to_string(body) == ~s({"address":"192.168.88.2/24","interface":"bridge"})
      assert Enum.any?(headers, fn {key, _value} -> to_string(key) == "authorization" end)

      {:ok, {201, [], ""}}
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, nil} =
             MikrotikApi.ip_address_add(
               auth,
               "10.0.0.1",
               %{"address" => "192.168.88.2/24", "interface" => "bridge"},
               scheme: :http
             )
  end

  test "owner_pid shares stubs with worker processes" do
    owner = self()
    Mock.stub(:get, "/system/resource", 200, %{"uptime" => "2h"})
    auth = Auth.new(username: "u", password: "p")

    task =
      Task.async(fn ->
        MikrotikApi.system_resource(auth, "10.0.0.1", scheme: :http, owner_pid: owner)
      end)

    assert {:ok, %{"uptime" => "2h"}} = Task.await(task)
  end
end
