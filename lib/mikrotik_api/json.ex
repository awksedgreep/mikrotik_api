defmodule MikrotikApi.JSON do
  @moduledoc false

  # Internal JSON codec (no external deps).
  # Supports objects, arrays, strings (common escapes), numbers, booleans, null.

  # -- Public API --

  def encode!(nil), do: "null"
  def encode!(true), do: "true"
  def encode!(false), do: "false"
  def encode!(n) when is_integer(n) or is_float(n), do: to_string(n)
  def encode!(s) when is_binary(s), do: ["\"", escape(s), "\""] |> IO.iodata_to_binary()
  def encode!(list) when is_list(list), do: ["[", encode_list(list), "]"] |> IO.iodata_to_binary()
  def encode!(%{} = map), do: ["{", encode_map(map), "}"] |> IO.iodata_to_binary()
  def encode!(other), do: raise(ArgumentError, "unsupported JSON encode: #{inspect(other)}")

  def decode(bin) when is_binary(bin) do
    {val, rest} = parse_value(skip_ws(bin))
    rest2 = skip_ws(rest)
    if rest2 == "" do
      {:ok, val}
    else
      {:error, {:trailing_data, rest2}}
    end
  rescue
    e in RuntimeError -> {:error, e.message}
  end

  # -- Encoder helpers --

  defp encode_list([]), do: []
  defp encode_list([h]), do: encode!(h)
  defp encode_list([h | t]), do: [encode!(h), "," | encode_list(t)]

  defp encode_map(map) when map_size(map) == 0, do: []
  defp encode_map(map) do
    map
    |> Enum.map(fn {k, v} -> [encode!(to_string(k)), ":", encode!(v)] end)
    |> Enum.intersperse(",")
  end

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  # -- Decoder (simple, pragmatic) --

  defp parse_value(<<?{, rest::binary>>), do: parse_object(skip_ws(rest), %{})
  defp parse_value(<<?[, rest::binary>>), do: parse_array(skip_ws(rest), [])
  defp parse_value(<<?\", rest::binary>>), do: parse_string(rest, [])
  defp parse_value(<<"null", rest::binary>>), do: {nil, rest}
  defp parse_value(<<"true", rest::binary>>), do: {true, rest}
  defp parse_value(<<"false", rest::binary>>), do: {false, rest}
  defp parse_value(<<c, _::binary>> = bin) when c in [?-, ?+, ?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9],
    do: parse_number(bin)
  defp parse_value(<<>>), do: raise "unexpected end of input"
  defp parse_value(bin), do: raise("invalid JSON value starting at: #{inspect(binary_part(bin, 0, min(byte_size(bin), 16)))}")

  # objects
  defp parse_object(<<?}, rest::binary>>, acc), do: {acc, rest}
  defp parse_object(<<?\", rest::binary>>, acc) do
    {key, rest2} = parse_string(rest, [])
    rest3 = skip_ws(rest2)
    case rest3 do
      <<?:, tail::binary>> ->
        {val, rest4} = parse_value(skip_ws(tail))
        rest5 = skip_ws(rest4)
        case rest5 do
          <<?,, more::binary>> -> parse_object(skip_ws(more), Map.put(acc, key, val))
          <<?}, tail2::binary>> -> {Map.put(acc, key, val), tail2}
          _ -> raise "invalid object, expected , or }"
        end
      _ -> raise "invalid object, expected : after key"
    end
  end
  defp parse_object(_, _), do: raise "invalid object"

  # arrays
  defp parse_array(<<?], rest::binary>>, acc), do: {Enum.reverse(acc), rest}
  defp parse_array(bin, acc) do
    {val, rest} = parse_value(bin)
    rest2 = skip_ws(rest)
    case rest2 do
      <<?,, more::binary>> -> parse_array(skip_ws(more), [val | acc])
      <<?], tail::binary>> -> {Enum.reverse([val | acc]), tail}
      _ -> raise "invalid array, expected , or ]"
    end
  end

  # strings
  defp parse_string(<<?\", rest::binary>>, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp parse_string(<<?\\, ?\", rest::binary>>, acc), do: parse_string(rest, ["\"" | acc])
  defp parse_string(<<?\\, ?\\, rest::binary>>, acc), do: parse_string(rest, ["\\" | acc])
  defp parse_string(<<?\\, ?/, rest::binary>>, acc), do: parse_string(rest, ["/" | acc])
  defp parse_string(<<?\\, ?b, rest::binary>>, acc), do: parse_string(rest, [<<8>> | acc])
  defp parse_string(<<?\\, ?f, rest::binary>>, acc), do: parse_string(rest, [<<12>> | acc])
  defp parse_string(<<?\\, ?n, rest::binary>>, acc), do: parse_string(rest, ["\n" | acc])
  defp parse_string(<<?\\, ?r, rest::binary>>, acc), do: parse_string(rest, ["\r" | acc])
  defp parse_string(<<?\\, ?t, rest::binary>>, acc), do: parse_string(rest, ["\t" | acc])
  defp parse_string(<<?\\, ?u, h1, h2, h3, h4, rest::binary>>, acc) do
    cp = hex4_to_codepoint(h1, h2, h3, h4)
    parse_string(rest, [<<cp::utf8>> | acc])
  end
  defp parse_string(<<c, rest::binary>>, acc), do: parse_string(rest, [<<c>> | acc])
  defp parse_string(<<>>, _), do: raise "unterminated string"

  defp hex4_to_codepoint(h1, h2, h3, h4) do
    <<h1, h2, h3, h4>>
    |> String.downcase()
    |> then(fn <<a, b, c, d>> ->
      :erlang.list_to_integer([a, b, c, d], 16)
    end)
  end

  # numbers
  defp parse_number(bin) do
    {num_str, rest} = take_while(bin, fn c -> c in '0123456789+-.eE' end)
    case Integer.parse(num_str) do
      {i, ""} -> {i, rest}
      _ ->
        case Float.parse(num_str) do
          {f, ""} -> {f, rest}
          _ -> raise "invalid number"
        end
    end
  end

  # utils
  defp skip_ws(<<c, rest::binary>>) when c in [9, 10, 13, 32], do: skip_ws(rest)
  defp skip_ws(rest), do: rest

  defp take_while(<<>>, _pred, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}
  defp take_while(<<c, rest::binary>>, pred, acc) do
    if pred.(c), do: take_while(rest, pred, [<<c>> | acc]), else: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  end
  defp take_while(bin, pred), do: take_while(bin, pred, [])
end
