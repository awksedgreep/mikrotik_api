defmodule MikrotikApi.NormalizeTest do
  use ExUnit.Case, async: true

  test "normalize_bool handles common variants" do
    assert MikrotikApi.Normalize.normalize_bool(true) == true
    assert MikrotikApi.Normalize.normalize_bool(false) == false
    assert MikrotikApi.Normalize.normalize_bool("true") == true
    assert MikrotikApi.Normalize.normalize_bool("False") == false
    assert MikrotikApi.Normalize.normalize_bool("yes") == true
    assert MikrotikApi.Normalize.normalize_bool("No") == false
    assert MikrotikApi.Normalize.normalize_bool("enabled") == true
    assert MikrotikApi.Normalize.normalize_bool("disabled") == false
    assert MikrotikApi.Normalize.normalize_bool("other") == "other"
  end

  test "to_int parses integers" do
    assert MikrotikApi.Normalize.to_int("1500") == 1500
    assert MikrotikApi.Normalize.to_int(" -64 ") == -64
    assert MikrotikApi.Normalize.to_int(10) == 10
    assert MikrotikApi.Normalize.to_int("x") == "x"
  end

  test "to_float parses floats" do
    assert MikrotikApi.Normalize.to_float("3.14") == 3.14
    assert MikrotikApi.Normalize.to_float("1.0e3") == 1000.0
    assert MikrotikApi.Normalize.to_float(2.5) == 2.5
    assert MikrotikApi.Normalize.to_float("x") == "x"
  end

  test "parse_rate_mbps parses Mbps" do
    assert MikrotikApi.Normalize.parse_rate_mbps("877 Mbps") == 877
    assert MikrotikApi.Normalize.parse_rate_mbps(" 54 Mbps ") == 54
    assert MikrotikApi.Normalize.parse_rate_mbps("1 Gbps") == "1 Gbps"
  end
end
