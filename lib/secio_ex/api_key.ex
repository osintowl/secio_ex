defmodule SecioEx.ApiKey do
  @moduledoc """
  Loads a sec-api.io key from an option, `SEC_API_KEY`, or `~/Desktop/sec.txt`.

  The key is never logged.
  """

  @default_file "~/Desktop/sec.txt"

  @doc """
  Resolves an API key.

  Options, in order:

    * `:api_key` — the key itself
    * `:api_key_file` — a file whose contents are the key
    * `SEC_API_KEY` in the environment
    * `~/Desktop/sec.txt` when that file exists
  """
  def resolve!(opts \\ []) do
    cond do
      present?(opts[:api_key]) ->
        String.trim(opts[:api_key])

      present?(opts[:api_key_file]) ->
        read!(opts[:api_key_file])

      present?(System.get_env("SEC_API_KEY")) ->
        String.trim(System.get_env("SEC_API_KEY"))

      File.regular?(Path.expand(@default_file)) ->
        read!(@default_file)

      true ->
        raise ArgumentError,
              "no SEC API key. Set SEC_API_KEY, pass --api-key-file, or add the key to ~/Desktop/sec.txt"
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp read!(path) do
    expanded = Path.expand(path)

    case File.read(expanded) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> raise ArgumentError, "API key file #{expanded} is empty"
          key -> key
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not read API key file #{expanded}: #{:file.format_error(reason)}"
    end
  end
end
