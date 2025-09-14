defmodule MikrotikApi.InterfaceEnsureByIdTest do
  use ExUnit.Case, async: true
  alias MikrotikApi.Auth

  setup do
    Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)
    :ok
  end

  test "interface_ensure by .id" do
    MikrotikApi.Transport.Mock.put(fn method, url, _headers, _body, _opts ->
      case {method, to_string(url)} do
        {:get, "http://10.0.0.1:80/rest/interface"} ->
          {:ok, {200, [], ~s([{".id":"*X","name":"etherX","disabled":"true"}])}}

        {:patch, "http://10.0.0.1:80/rest/interface/*X"} ->
          {:ok, {200, [], ""}}
      end
    end)

    auth = Auth.new(username: "u", password: "p")

    assert {:ok, %{id: "*X", name: "etherX", changed: ["disabled"]}} =
             MikrotikApi.interface_ensure(auth, "10.0.0.1", "*X", %{"disabled" => "false"},
               scheme: :http
             )
  end
end
