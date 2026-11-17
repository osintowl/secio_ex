defmodule SecioEx.StreamTlsTest do
  use ExUnit.Case, async: true

  test "the filing socket verifies the server certificate" do
    opts = SecioEx.StreamApi.connection_options(name: :secio_stream, async: false)
    assert opts[:async] == false
    assert opts[:name] == :secio_stream
    assert opts[:handle_initial_conn_failure] == true
    assert opts[:insecure] == false

    conn = WebSockex.Conn.new("wss://stream.sec-api.io", opts)
    assert conn.insecure == false
    assert conn.ssl_options[:verify] == :verify_peer
    assert conn.ssl_options[:cacerts] == conn.cacerts
    assert conn.cacerts != []
    assert Enum.all?(conn.cacerts, &is_binary/1)

    forced = SecioEx.StreamApi.connection_options(insecure: true)
    assert forced[:insecure] == false
    assert forced[:ssl_options][:verify] == :verify_peer
  end
end
