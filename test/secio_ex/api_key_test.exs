defmodule SecioEx.ApiKeyTest do
  use ExUnit.Case, async: true

  test "reads a trimmed key from a file" do
    path = Path.join(System.tmp_dir!(), "secio-key-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "\n  test-key  \n")
    on_exit(fn -> File.rm(path) end)

    assert SecioEx.ApiKey.resolve!(api_key_file: path) == "test-key"
  end

  test "an explicit key is trimmed" do
    assert SecioEx.ApiKey.resolve!(api_key: " from-opt ") == "from-opt"
  end

  test "a missing key file raises" do
    assert_raise ArgumentError, ~r/could not read API key file/, fn ->
      SecioEx.ApiKey.resolve!(
        api_key_file: "/tmp/secio-missing-key-#{System.unique_integer([:positive])}"
      )
    end
  end
end
