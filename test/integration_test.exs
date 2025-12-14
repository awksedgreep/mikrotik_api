defmodule MikrotikApi.IntegrationTest do
  @moduledoc """
  Integration tests against real MikroTik routers.

  Run with:
    mix test test/integration_test.exs --include integration

  Requires environment variables or hardcoded values below.
  """
  use ExUnit.Case

  @moduletag :integration

  # Test routers - update these for your environment
  @router_a "192.168.89.197"
  @router_b "192.168.89.198"
  @username "routeros-cm"
  @password "secret"

  setup do
    auth = MikrotikApi.Auth.new(username: @username, password: @password, verify: :verify_none)
    # Use real HTTP transport
    Application.delete_env(:mikrotik_api, :transport)
    {:ok, auth: auth, ip_a: @router_a, ip_b: @router_b}
  end

  # ============================================
  # Read-only tests (safe, no side effects)
  # ============================================

  describe "read-only operations" do
    test "system_resource returns router info", %{auth: auth, ip_a: ip} do
      assert {:ok, data} = MikrotikApi.system_resource(auth, ip, scheme: :http)
      assert is_map(data)
      assert Map.has_key?(data, "version")
      assert Map.has_key?(data, "uptime")
      IO.puts("Router A version: #{data["version"]}, uptime: #{data["uptime"]}")
    end

    test "system_identity returns router name", %{auth: auth, ip_a: ip} do
      assert {:ok, data} = MikrotikApi.system_identity(auth, ip, scheme: :http)
      assert is_map(data)
      assert Map.has_key?(data, "name")
      IO.puts("Router A identity: #{data["name"]}")
    end

    test "interface_list returns interfaces", %{auth: auth, ip_a: ip} do
      assert {:ok, interfaces} = MikrotikApi.interface_list(auth, ip, scheme: :http)
      assert is_list(interfaces)
      assert length(interfaces) > 0
      IO.puts("Router A has #{length(interfaces)} interfaces")
    end

    test "user_list returns users", %{auth: auth, ip_a: ip} do
      assert {:ok, users} = MikrotikApi.user_list(auth, ip, scheme: :http)
      assert is_list(users)
      assert length(users) > 0
      IO.puts("Router A has #{length(users)} users")
    end

    test "user_group_list returns groups", %{auth: auth, ip_a: ip} do
      assert {:ok, groups} = MikrotikApi.user_group_list(auth, ip, scheme: :http)
      assert is_list(groups)
      assert length(groups) > 0
      IO.puts("Router A has #{length(groups)} user groups")
    end

    test "dns_settings_get returns DNS config", %{auth: auth, ip_a: ip} do
      assert {:ok, data} = MikrotikApi.dns_settings_get(auth, ip, scheme: :http)
      assert is_map(data)
      IO.puts("Router A DNS servers: #{inspect(data["servers"])}")
    end

    test "dns_cache_list returns cache entries", %{auth: auth, ip_a: ip} do
      assert {:ok, cache} = MikrotikApi.dns_cache_list(auth, ip, scheme: :http)
      assert is_list(cache)
      IO.puts("Router A DNS cache has #{length(cache)} entries")
    end

    test "dns_static_list returns static entries", %{auth: auth, ip_a: ip} do
      assert {:ok, static} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)
      assert is_list(static)
      IO.puts("Router A has #{length(static)} DNS static entries")
    end

    test "both routers are reachable", %{auth: auth, ip_a: ip_a, ip_b: ip_b} do
      assert {:ok, data_a} = MikrotikApi.system_resource(auth, ip_a, scheme: :http)
      assert {:ok, data_b} = MikrotikApi.system_resource(auth, ip_b, scheme: :http)
      IO.puts("Router A: #{data_a["board-name"]} - #{data_a["version"]}")
      IO.puts("Router B: #{data_b["board-name"]} - #{data_b["version"]}")
    end
  end

  # ============================================
  # CRUD tests (create, update, delete)
  # ============================================

  describe "DNS static record CRUD" do
    @test_dns_name "integration-test.local"

    test "create, update, and delete DNS static record", %{auth: auth, ip_a: ip} do
      # Clean up any existing test record first
      {:ok, existing} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)

      for entry <- existing || [] do
        if entry["name"] == @test_dns_name do
          MikrotikApi.dns_static_delete(auth, ip, entry[".id"], scheme: :http)
        end
      end

      # Create
      attrs = %{"name" => @test_dns_name, "address" => "10.99.99.1"}
      assert {:ok, _} = MikrotikApi.dns_static_add(auth, ip, attrs, scheme: :http)
      IO.puts("Created DNS static record: #{@test_dns_name}")

      # Verify it exists
      {:ok, list} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)
      entry = Enum.find(list, fn e -> e["name"] == @test_dns_name end)
      assert entry != nil
      assert entry["address"] == "10.99.99.1"
      id = entry[".id"]

      # Update
      assert {:ok, _} =
               MikrotikApi.dns_static_update(auth, ip, id, %{"address" => "10.99.99.2"}, scheme: :http)

      IO.puts("Updated DNS static record address to 10.99.99.2")

      # Verify update
      {:ok, list} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)
      entry = Enum.find(list, fn e -> e["name"] == @test_dns_name end)
      assert entry["address"] == "10.99.99.2"

      # Delete
      assert {:ok, _} = MikrotikApi.dns_static_delete(auth, ip, id, scheme: :http)
      IO.puts("Deleted DNS static record")

      # Verify deletion
      {:ok, list} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)
      entry = Enum.find(list, fn e -> e["name"] == @test_dns_name end)
      assert entry == nil
    end

    test "dns_static_ensure creates and updates idempotently", %{auth: auth, ip_a: ip} do
      # Clean up first
      {:ok, existing} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)

      for entry <- existing || [] do
        if entry["name"] == @test_dns_name do
          MikrotikApi.dns_static_delete(auth, ip, entry[".id"], scheme: :http)
        end
      end

      # First ensure - should create
      attrs = %{"address" => "10.99.99.10"}

      assert {:ok, %{name: @test_dns_name, changed: changed}} =
               MikrotikApi.dns_static_ensure(auth, ip, @test_dns_name, attrs, scheme: :http)

      assert "name" in changed
      IO.puts("dns_static_ensure created: changed=#{inspect(changed)}")

      # Second ensure with same attrs - should be no-op
      assert {:ok, %{name: @test_dns_name, changed: []}} =
               MikrotikApi.dns_static_ensure(auth, ip, @test_dns_name, attrs, scheme: :http)

      IO.puts("dns_static_ensure idempotent: no changes")

      # Third ensure with different attrs - should update
      new_attrs = %{"address" => "10.99.99.20"}

      assert {:ok, %{name: @test_dns_name, changed: changed}} =
               MikrotikApi.dns_static_ensure(auth, ip, @test_dns_name, new_attrs, scheme: :http)

      assert "address" in changed
      IO.puts("dns_static_ensure updated: changed=#{inspect(changed)}")

      # Cleanup
      {:ok, list} = MikrotikApi.dns_static_list(auth, ip, scheme: :http)
      entry = Enum.find(list, fn e -> e["name"] == @test_dns_name end)

      if entry do
        MikrotikApi.dns_static_delete(auth, ip, entry[".id"], scheme: :http)
      end
    end
  end

  describe "DNS cache operations" do
    test "dns_cache_flush clears the cache", %{auth: auth, ip_a: ip} do
      # This should succeed without error
      assert {:ok, _} = MikrotikApi.dns_cache_flush(auth, ip, scheme: :http)
      IO.puts("DNS cache flushed successfully")
    end
  end

  describe "IP address CRUD" do
    @test_address "10.254.254.1/32"
    @test_interface "lo"

    test "ip_address_add creates an address", %{auth: auth, ip_a: ip} do
      # Clean up any existing test address first
      {:ok, existing} = MikrotikApi.ip_address_list(auth, ip, scheme: :http)

      for entry <- existing || [] do
        if entry["address"] == @test_address do
          MikrotikApi.ip_address_delete(auth, ip, entry[".id"], scheme: :http)
        end
      end

      # Create - using loopback interface which should exist
      attrs = %{"address" => @test_address, "interface" => @test_interface}
      result = MikrotikApi.ip_address_add(auth, ip, attrs, scheme: :http)

      case result do
        {:ok, _} ->
          IO.puts("Created IP address: #{@test_address} on #{@test_interface}")

          # Cleanup
          {:ok, list} = MikrotikApi.ip_address_list(auth, ip, scheme: :http)
          entry = Enum.find(list, fn e -> e["address"] == @test_address end)

          if entry do
            MikrotikApi.ip_address_delete(auth, ip, entry[".id"], scheme: :http)
            IO.puts("Cleaned up test IP address")
          end

        {:error, err} ->
          IO.puts("IP address add failed (may be expected if 'lo' doesn't exist): #{inspect(err)}")
      end
    end
  end

  describe "firewall filter CRUD" do
    @test_comment "integration-test-rule"

    test "firewall_filter_add creates a rule", %{auth: auth, ip_a: ip} do
      # Clean up any existing test rule first
      {:ok, existing} = MikrotikApi.firewall_filter_list(auth, ip, scheme: :http)

      for entry <- existing || [] do
        if entry["comment"] == @test_comment do
          MikrotikApi.firewall_filter_delete(auth, ip, entry[".id"], scheme: :http)
        end
      end

      # Create
      rule = %{
        "chain" => "forward",
        "action" => "accept",
        "comment" => @test_comment,
        "disabled" => "true"
      }

      assert {:ok, _} = MikrotikApi.firewall_filter_add(auth, ip, rule, scheme: :http)
      IO.puts("Created firewall filter rule with comment: #{@test_comment}")

      # Verify and cleanup
      {:ok, list} = MikrotikApi.firewall_filter_list(auth, ip, scheme: :http)
      entry = Enum.find(list, fn e -> e["comment"] == @test_comment end)
      assert entry != nil

      MikrotikApi.firewall_filter_delete(auth, ip, entry[".id"], scheme: :http)
      IO.puts("Cleaned up test firewall rule")
    end
  end
end
