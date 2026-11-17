defmodule SecioEx.ClientTest do
  use ExUnit.Case, async: true

  @key "unit-test-key"

  test "the shared Finch pool sends header authentication and decodes JSON" do
    handler = make_ref()

    :ok =
      :telemetry.attach(
        handler,
        [:finch, :request, :start],
        &__MODULE__.record_finch_pool/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    url = serve([{200, ~s({"ok":true})}])

    assert {:ok, %{"ok" => true}} = SecioEx.Client.get_absolute(url, api_key: @key)
    assert_receive {:request, request}
    assert request =~ "GET / HTTP/1.1\r\n"
    assert String.downcase(request) =~ "authorization: #{@key}\r\n"
    refute request =~ "token="
    assert_received {:finch_pool, SecioEx.Finch}
  end

  test "query authentication preserves parameters and omits the authorization header" do
    url = serve([{200, ~s({"ok":true})}])

    assert {:ok, %{"ok" => true}} =
             SecioEx.Client.get_absolute(url,
               api_key: @key,
               auth: :query,
               params: %{"ticker" => "AAPL"}
             )

    assert_receive {:request, request}
    ["GET", path | _] = String.split(request, " ", parts: 3)
    assert URI.decode_query(URI.parse(path).query) == %{"ticker" => "AAPL", "token" => @key}
    refute String.downcase(request) =~ "authorization:"
  end

  for status <- [201, 204, 299] do
    test "HTTP #{status} is accepted as a successful response" do
      status = unquote(status)
      body = if status == 204, do: "", else: ~s({"ok":true})
      expected = if status == 204, do: "", else: %{"ok" => true}
      url = serve([{status, body}])

      assert {:ok, ^expected} = SecioEx.Client.get_absolute(url, api_key: @key)
      assert_receive {:request, _}
      refute_received {:request, _}
    end
  end

  for status <- [401, 404] do
    test "HTTP #{status} is returned without retrying and redacts nested keys" do
      status = unquote(status)
      body = Jason.encode!(%{"errors" => [%{"message" => "invalid #{@key}"}], @key => @key})
      url = serve([{status, body}])

      assert {:error, %{status_code: ^status, body: body}} =
               SecioEx.Client.get_absolute(url, api_key: @key)

      assert body == %{
               "errors" => [%{"message" => "invalid [redacted]"}],
               "[redacted]" => "[redacted]"
             }

      assert_receive {:request, _}
      refute_received {:request, _}
    end
  end

  for status <- [408, 429, 500, 502, 503, 504] do
    test "HTTP #{status} is retried and can recover" do
      url = serve([{unquote(status), ~s({"error":"unavailable"})}, {200, ~s({"ok":true})}])

      assert {:ok, %{"ok" => true}} =
               SecioEx.Client.get_absolute(url, api_key: @key, max_retries: 1)

      assert_receive {:request, _}
      assert_receive {:request, _}
      refute_received {:request, _}
    end
  end

  test "exhausting the retry budget returns the final HTTP error" do
    url = serve([{503, ~s({"attempt":1})}, {503, ~s({"attempt":2})}])

    assert {:error, %{status_code: 503, body: %{"attempt" => 2}}} =
             SecioEx.Client.get_absolute(url, api_key: @key, max_retries: 1)

    assert_receive {:request, _}
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  test "a retried POST preserves the JSON body and authentication" do
    url = serve([{503, ~s({"error":"unavailable"})}, {200, ~s({"ok":true})}])
    body = %{"query" => "ticker:AAPL", "from" => 0, "size" => 50}

    assert {:ok, %{"ok" => true}} =
             SecioEx.Client.post(url, body, api_key: @key, max_retries: 1)

    for _ <- 1..2 do
      assert_receive {:request, request}
      assert request =~ "POST / HTTP/1.1\r\n"
      assert String.downcase(request) =~ "authorization: #{@key}\r\n"
      [headers, encoded_body] = String.split(request, "\r\n\r\n", parts: 2)
      assert String.downcase(headers) =~ "content-type: application/json"
      assert Jason.decode!(encoded_body) == body
    end

    refute_received {:request, _}
  end

  test "a zero retry budget returns a transient response after one request" do
    url = serve([{503, ~s({"error":"unavailable"})}])

    assert {:error, %{status_code: 503, body: %{"error" => "unavailable"}}} =
             SecioEx.Client.get_absolute(url, api_key: @key, max_retries: 0)

    assert_receive {:request, _}
    refute_received {:request, _}
  end

  test "a closed connection returns a transport error" do
    url = serve([:close])

    assert {:error, %Req.TransportError{}} =
             SecioEx.Client.get_absolute(url, api_key: @key, max_retries: 0)

    assert_receive {:request, _}
    refute_received {:request, _}
  end

  test "a closed connection is retried and can recover" do
    url = serve([:close, {200, ~s({"ok":true})}])

    assert {:ok, %{"ok" => true}} =
             SecioEx.Client.get_absolute(url, api_key: @key, max_retries: 1)

    assert_receive {:request, _}
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  test "a gzip file is returned as bytes without automatic archive decoding" do
    body = :zlib.gzip("filing data")
    url = serve([{200, body, "application/gzip"}])

    assert {:ok, ^body} = SecioEx.Client.get_absolute(url, api_key: @key)
  end

  test "a zip file is returned as bytes without automatic archive extraction" do
    {:ok, {_, body}} =
      :zip.create(~c"filings.zip", [{~c"filing.txt", "filing data"}], [:memory])

    url = serve([{200, body, "application/zip"}])

    assert {:ok, ^body} = SecioEx.Client.get_absolute(url, api_key: @key)
  end

  test "a gzip file streams to disk without changing its bytes" do
    body = :zlib.gzip("filing data")
    url = serve([{200, body, "application/gzip"}])
    path = Path.join(System.tmp_dir!(), "secio-client-#{System.unique_integer([:positive])}.gz")
    on_exit(fn -> File.rm(path) end)
    stream = File.stream!(path, [:write, :binary])

    assert {:ok, _} =
             SecioEx.Client.get_absolute(url, api_key: @key, into: stream, decode_body: false)

    assert File.read!(path) == body
    assert :zlib.gunzip(File.read!(path)) == "filing data"
  end

  @tag :tmp_dir
  test "a dataset download authenticates and publishes the unchanged gzip file", %{tmp_dir: dir} do
    body = :zlib.gzip("filing data")
    url = serve([{200, body, "application/gzip"}])
    details = dataset(url, byte_size(body))
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:ok, [^path]} = SecioEx.Datasets.download(details, path: dir, api_key: @key)
    assert File.read!(path) == body
    refute File.exists?(path <> ".partial")
    assert_receive {:request, request}
    ["GET", target | _] = String.split(request, " ", parts: 3)
    assert URI.decode_query(URI.parse(target).query) == %{"token" => @key}
    refute String.downcase(request) =~ "authorization:"
  end

  @tag :tmp_dir
  test "HTTP gzip encoding is removed while the dataset gzip bytes are preserved", %{tmp_dir: dir} do
    body = :zlib.gzip("filing data")
    url = serve([{200, :zlib.gzip(body), "application/gzip", [{"content-encoding", "gzip"}]}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:ok, [^path]} =
             SecioEx.Datasets.download(dataset(url, byte_size(body)), path: dir, api_key: @key)

    assert File.read!(path) == body
    assert :zlib.gunzip(File.read!(path)) == "filing data"
    refute File.exists?(path <> ".partial")
    assert_receive {:request, request}
    refute String.downcase(request) =~ "accept-encoding:"
  end

  @tag :tmp_dir
  test "a large HTTP gzip response streams through multiple decoder buffers", %{tmp_dir: dir} do
    contents = for index <- 1..50_000, into: <<>>, do: <<index::32>>
    body = :zlib.gzip(contents)
    assert byte_size(body) > 65_536
    url = serve([{200, :zlib.gzip(body), "application/gzip", [{"content-encoding", "gzip"}]}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:ok, [^path]} =
             SecioEx.Datasets.download(dataset(url, byte_size(body)), path: dir, api_key: @key)

    assert File.read!(path) == body
    assert :zlib.gunzip(File.read!(path)) == contents
  end

  for {name, encoded} <- [
        {"invalid", "invalid gzip"},
        {"truncated", :zlib.gzip("filing data") |> binary_part(0, 15)}
      ] do
    @tag :tmp_dir
    test "a malformed (#{name}) HTTP gzip response removes the partial dataset file", %{
      tmp_dir: dir
    } do
      url = serve([{200, unquote(encoded), "application/gzip", [{"content-encoding", "gzip"}]}])
      path = Path.join(dir, "filings.jsonl.gz")

      assert {:error, %{reason: :invalid_gzip}} =
               SecioEx.Datasets.download(dataset(url, nil), path: dir, api_key: @key)

      refute File.exists?(path)
      refute File.exists?(path <> ".partial")
    end
  end

  @tag :tmp_dir
  test "unsupported HTTP content encoding removes the partial dataset file", %{tmp_dir: dir} do
    url = serve([{200, "encoded data", "application/gzip", [{"content-encoding", "br"}]}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:error, %{reason: :unsupported_content_encoding}} =
             SecioEx.Datasets.download(dataset(url, nil), path: dir, api_key: @key)

    refute File.exists?(path)
    refute File.exists?(path <> ".partial")
  end

  @tag :tmp_dir
  test "a disconnected dataset transfer removes the partial file without retrying", %{
    tmp_dir: dir
  } do
    url = serve([{:disconnect, "partial data"}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:error, %Req.TransportError{}} =
             SecioEx.Datasets.download(dataset(url, nil), path: dir, api_key: @key)

    refute File.exists?(path)
    refute File.exists?(path <> ".partial")
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  @tag :tmp_dir
  test "an opted-in dataset retry replaces the interrupted transfer", %{tmp_dir: dir} do
    body = :zlib.gzip("filing data")
    url = serve([{:disconnect, "partial data"}, {200, body, "application/gzip"}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:ok, [^path]} =
             SecioEx.Datasets.download(dataset(url, byte_size(body)),
               path: dir,
               api_key: @key,
               max_retries: 1
             )

    assert File.read!(path) == body
    refute File.exists?(path <> ".partial")
    assert_receive {:request, _}
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  @tag :tmp_dir
  test "an opted-in retry can replace a partial transfer with an empty file", %{tmp_dir: dir} do
    url = serve([{:disconnect, "partial data"}, {200, "", "application/octet-stream"}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:ok, [^path]} =
             SecioEx.Datasets.download(dataset(url, 0),
               path: dir,
               api_key: @key,
               max_retries: 1
             )

    assert File.read!(path) == ""
    refute File.exists?(path <> ".partial")
    assert_receive {:request, _}
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  @tag :tmp_dir
  test "a dataset size mismatch removes the partial file", %{tmp_dir: dir} do
    body = :zlib.gzip("filing data")
    url = serve([{200, body, "application/gzip"}])
    actual = byte_size(body)
    expected = actual + 1
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:error, %{reason: :size_mismatch, path: ^path, expected: ^expected, actual: ^actual}} =
             SecioEx.Datasets.download(dataset(url, expected), path: dir, api_key: @key)

    refute File.exists?(path)
    refute File.exists?(path <> ".partial")
  end

  @tag :tmp_dir
  test "a failed dataset transfer returns a redacted error and removes the partial file", %{
    tmp_dir: dir
  } do
    url = serve([{503, Jason.encode!(%{"error" => "unavailable #{@key}"})}])
    path = Path.join(dir, "filings.jsonl.gz")

    assert {:error, %{status_code: 503, body: body}} =
             SecioEx.Datasets.download(dataset(url, 0), path: dir, api_key: @key)

    assert body == ~s({"error":"unavailable [redacted]"})
    refute File.exists?(path)
    refute File.exists?(path <> ".partial")
    assert_receive {:request, _}
    refute_received {:request, _}
  end

  defp dataset(url, size) do
    %{"containers" => [%{"key" => "filings.jsonl.gz", "downloadUrl" => url, "size" => size}]}
  end

  @doc false
  def record_finch_pool(_event, _measurements, metadata, test_pid) do
    if self() == test_pid, do: send(test_pid, {:finch_pool, metadata.name})
  end

  # Exercise Req and the supervised Finch pool over actual HTTP, without a Plug adapter.
  defp serve(responses) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listener)
    parent = self()
    on_exit(fn -> :gen_tcp.close(listener) end)

    start_supervised!(%{
      id: make_ref(),
      start:
        {Task, :start_link,
         [
           fn ->
             Enum.each(responses, fn response ->
               {:ok, socket} = :gen_tcp.accept(listener, 5_000)
               send(parent, {:request, read_request(socket)})

               case response do
                 :close ->
                   :ok

                 {:disconnect, body} ->
                   :ok =
                     :gen_tcp.send(socket, [
                       "HTTP/1.1 200 Response\r\n",
                       "content-length: #{byte_size(body) + 10}\r\n",
                       "connection: close\r\n\r\n",
                       body
                     ])

                 {status, body} ->
                   respond(socket, status, body, "application/json")

                 {status, body, content_type} ->
                   respond(socket, status, body, content_type)

                 {status, body, content_type, headers} ->
                   respond(socket, status, body, content_type, headers)
               end

               :gen_tcp.close(socket)
             end)

             :gen_tcp.close(listener)
           end
         ]},
      restart: :temporary
    })

    "http://127.0.0.1:#{port}/"
  end

  defp respond(socket, status, body, content_type, headers \\ []) do
    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 #{status} Response\r\n",
        "content-type: #{content_type}\r\n",
        "content-length: #{byte_size(body)}\r\n",
        Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
        "connection: close\r\n\r\n",
        body
      ])
  end

  defp read_headers(socket, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      acc
    else
      {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
      read_headers(socket, acc <> chunk)
    end
  end

  defp read_request(socket) do
    [headers, body] = socket |> read_headers("") |> String.split("\r\n\r\n", parts: 2)

    length =
      case Regex.run(~r/\r\ncontent-length: (\d+)/i, headers) do
        [_, value] -> String.to_integer(value)
        nil -> 0
      end

    headers <> "\r\n\r\n" <> read_body(socket, body, length)
  end

  defp read_body(socket, body, length) when byte_size(body) < length do
    {:ok, chunk} = :gen_tcp.recv(socket, length - byte_size(body), 5_000)
    read_body(socket, body <> chunk, length)
  end

  defp read_body(_socket, body, _length), do: body
end
