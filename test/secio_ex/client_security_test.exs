defmodule SecioEx.ClientSecurityTest do
  use ExUnit.Case, async: true

  @key "unit-test-key"

  test "decodes one gzip json body and asks only for gzip" do
    body = :zlib.gzip(Jason.encode!(%{"ok" => true}))

    assert {:ok, %{"ok" => true}} =
             SecioEx.Client.get("/float",
               api_key: @key,
               plug: gzip_plug(body, "application/json")
             )

    assert_received {:http, "GET", "api.sec-api.io", "/float", _, _, headers}
    assert header(headers, "accept-encoding") == "gzip"
  end

  test "follows a same-host redirect and decodes the gzip body" do
    body = :zlib.gzip(Jason.encode!(%{"ok" => true}))

    plug = fn conn ->
      if conn.request_path == "/start" do
        conn
        |> Plug.Conn.put_resp_header("location", "/float")
        |> Plug.Conn.send_resp(302, "")
      else
        send(self(), {:http, conn.host, conn.request_path})
        gzip_response(conn, body, "application/json")
      end
    end

    assert {:ok, %{"ok" => true}} = SecioEx.Client.get("/start", api_key: @key, plug: plug)
    assert_received {:http, "api.sec-api.io", "/float"}
  end

  test "does not follow a redirect onto another host" do
    plug = fn conn ->
      send(self(), {:hit, conn.host})

      if conn.host == "api.sec-api.io" do
        conn
        |> Plug.Conn.put_resp_header("location", "https://evil.example/bomb")
        |> Plug.Conn.send_resp(302, "")
      else
        conn
        |> Plug.Conn.put_resp_header("content-encoding", "gzip")
        |> Plug.Conn.send_resp(200, :zlib.gzip("expanded-bomb"))
      end
    end

    assert {:error, %{status_code: 302}} =
             SecioEx.Client.get("/float", api_key: @key, plug: plug)

    assert_received {:hit, "api.sec-api.io"}
    refute_received {:hit, "evil.example"}
  end

  test "rejects stacked gzip encodings without returning the inner body" do
    body = "stacked-secret" |> :zlib.gzip() |> :zlib.gzip()

    assert {:error, %{reason: :unsupported_encoding}} =
             SecioEx.Client.get("/float",
               api_key: @key,
               plug: gzip_plug(body, "text/plain", "gzip, gzip")
             )
  end

  test "rejects a gzip body one byte past the cap and accepts one at the cap" do
    assert {:ok, "abcd"} =
             SecioEx.Client.get("/float",
               api_key: @key,
               max_inflated_bytes: 4,
               plug: gzip_plug(:zlib.gzip("abcd"), "text/plain")
             )

    assert {:error, %{reason: :inflated_too_large}} =
             SecioEx.Client.get("/float",
               api_key: @key,
               max_inflated_bytes: 4,
               plug: gzip_plug(:zlib.gzip("abcde"), "text/plain")
             )
  end

  test "rejects a gzip body whose expansion ratio exceeds the cap" do
    payload = String.duplicate("a", 500)
    compressed = :zlib.gzip(payload)

    assert {:error, %{reason: :inflated_too_large}} =
             SecioEx.Client.get("/float",
               api_key: @key,
               max_inflated_bytes: 1_000_000,
               min_inflated_bytes: 1,
               max_inflate_ratio: 2,
               plug: gzip_plug(compressed, "text/plain")
             )

    assert byte_size(compressed) * 2 < byte_size(payload)
  end

  test "rejects a body that claims gzip but is not gzip" do
    assert {:error, %{reason: :invalid_encoding}} =
             SecioEx.Client.get("/float",
               api_key: @key,
               plug: gzip_plug("not-gzip", "text/plain")
             )
  end

  test "treats a trailing identity coding as one gzip encoding" do
    assert {:ok, "plain"} =
             SecioEx.Client.get("/float",
               api_key: @key,
               plug: gzip_plug(:zlib.gzip("plain"), "text/plain", "gzip, identity")
             )
  end

  defp gzip_plug(body, content_type, encoding \\ "gzip") do
    fn conn ->
      send(
        self(),
        {:http, conn.method, conn.host, conn.request_path, conn.query_params, nil,
         conn.req_headers}
      )

      gzip_response(conn, body, content_type, encoding)
    end
  end

  defp gzip_response(conn, body, content_type, encoding \\ "gzip") do
    conn
    |> Plug.Conn.put_resp_content_type(content_type)
    |> Plug.Conn.put_resp_header("content-encoding", encoding)
    |> Plug.Conn.send_resp(200, body)
  end

  defp header(headers, wanted) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(to_string(name)) == wanted, do: value
    end)
  end
end
