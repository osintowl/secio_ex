defmodule SecioEx.Datasets do
  @moduledoc """
  Bulk dataset index and file download.

  `list/1` reads `GET /bulk/indicies/master/index.json`. `details/2` reads
  `GET /datasets/:name.json`. `download/2` writes the container files, or one
  zip, into the directory given by `:path`.

  Downloads stream to `path <> ".partial"` and are renamed when the size
  matches. A file already at the expected size is skipped. Pass
  `strategy: :zip` to use `datasetDownloadUrl`. The default strategy is
  `:containers`. There is no default directory: a missing `:path` raises
  before any request when the details map is already in hand, and before the
  file transfer after details are fetched.

  The token is sent as a query parameter on the file URL. File bodies are not
  JSON-decoded and are not loaded into memory. HTTP content-encoding is
  unwrapped; a `.jsonl.gz` object stays gzip. File transfers are not retried.
  """

  @index "https://api.sec-api.io/bulk/indicies/master/index.json"

  @doc "List the bulk datasets."
  def list(opts \\ []) do
    SecioEx.Client.get(@index, opts)
  end

  @doc "Details for one dataset, including container URLs and sizes."
  def details(name, opts \\ []) when is_binary(name) do
    name = String.trim(name)

    if name == "" or String.contains?(name, "..") or String.contains?(name, "/") or
         String.contains?(name, "\\") do
      raise ArgumentError, "invalid dataset name"
    end

    SecioEx.Client.get("/datasets/#{SecioEx.Client.encode_segment(name)}.json", opts)
  end

  @doc """
  Plan the files a download would write.

  Returns `{:ok, files}` or `{:error, %{reason: reason}}`. Each file has
  `:url`, `:key`, and `:size`. A key that contains `..` or starts with `/`
  is `{:error, %{reason: :invalid_key, key: key}}`.
  """
  def plan(details, strategy \\ :containers) when is_map(details) do
    with :ok <- known_strategy(strategy),
         {:ok, files} <- entries(details, strategy) do
      validate_keys(files)
    end
  end

  @doc """
  Download a dataset into `:path`.

  `dataset` is a dataset name or the details map from `details/2`. `:strategy`
  is `:containers` (default) or `:zip`. Returns `{:ok, paths}`.
  """
  def download(dataset, opts \\ [])

  def download(name, opts) when is_binary(name) do
    ensure_path!(opts)

    case details(name, opts) do
      {:ok, body} when is_map(body) -> write_dataset(body, opts)
      {:ok, other} -> {:error, %{reason: :invalid_details, body: other}}
      {:error, _} = error -> error
    end
  end

  def download(details, opts) when is_map(details) do
    ensure_path!(opts)
    write_dataset(details, opts)
  end

  defp write_dataset(details, opts) do
    dir = ensure_path!(opts)
    File.mkdir_p!(dir)

    case plan(details, strategy!(opts)) do
      {:ok, files} -> download_files(files, dir, opts)
      {:error, _} = error -> error
    end
  end

  defp download_files(files, dir, opts) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, paths} ->
      case download_file(file, dir, opts) do
        {:ok, path} -> {:cont, {:ok, paths ++ [path]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp download_file(%{key: key, url: url, size: size}, dir, opts) do
    dest = Path.join(dir, key)

    cond do
      local_ready?(dest, size) ->
        {:ok, dest}

      not is_binary(url) or url == "" ->
        {:error, %{reason: :missing_url, key: key}}

      true ->
        File.mkdir_p!(Path.dirname(dest))
        partial = dest <> ".partial"
        stream = File.stream!(partial, 65_536, [:write, :binary])

        result =
          SecioEx.Client.get_absolute(
            url,
            Keyword.merge(opts,
              into: stream,
              decode_body: false,
              compressed: true,
              auth: :query,
              receive_timeout: Keyword.get(opts, :receive_timeout, 600_000),
              max_retries: Keyword.get(opts, :max_retries, 0)
            )
          )

        case result do
          {:ok, _body} ->
            finish_partial(partial, dest, size)

          {:error, reason} ->
            File.rm(partial)
            {:error, reason}
        end
    end
  end

  defp finish_partial(partial, dest, expected) do
    case File.stat(partial) do
      {:ok, %{size: actual, type: :regular}} ->
        if is_integer(expected) and actual != expected do
          File.rm(partial)
          {:error, %{reason: :size_mismatch, path: dest, expected: expected, actual: actual}}
        else
          File.rename!(partial, dest)
          {:ok, dest}
        end

      _ ->
        File.rm(partial)
        {:error, %{reason: :empty_download, path: dest}}
    end
  end

  defp entries(details, :containers) do
    containers = field(details, :containers) || []

    cond do
      not is_list(containers) ->
        {:error, %{reason: "dataset has no containers"}}

      containers == [] ->
        {:error, %{reason: "dataset has no containers"}}

      true ->
        {:ok,
         Enum.map(containers, fn container ->
           %{
             url: field(container, :downloadUrl),
             key: field(container, :key),
             size: field(container, :size)
           }
         end)}
    end
  end

  defp entries(details, :zip) do
    case field(details, :datasetDownloadUrl) do
      url when is_binary(url) and url != "" ->
        {:ok, [%{url: url, key: zip_name(url), size: nil}]}

      _ ->
        {:error, %{reason: "dataset has no download url"}}
    end
  end

  defp validate_keys(files) do
    case Enum.find(files, &(not valid_key?(&1.key))) do
      nil -> {:ok, files}
      file -> {:error, %{reason: :invalid_key, key: file.key}}
    end
  end

  defp valid_key?(key) when is_binary(key) do
    key != "" and key != "." and key != ".." and not String.starts_with?(key, "/") and
      not String.contains?(key, "..") and not String.contains?(String.downcase(key), "%2e%2e") and
      not String.contains?(key, "\\")
  end

  defp valid_key?(_key), do: false

  defp zip_name(url) do
    name =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> to_string()
      |> Path.basename()

    if name in ["", ".", ".."], do: "dataset.zip", else: name
  end

  defp field(map, key) when is_atom(key) and is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp field(_map, _key), do: nil

  defp local_ready?(dest, size) when is_integer(size) and size >= 0 do
    match?({:ok, %{size: ^size, type: :regular}}, File.stat(dest))
  end

  defp local_ready?(_dest, _size), do: false

  defp ensure_path!(opts) do
    path = opts[:path]

    unless is_binary(path) and String.trim(path) != "" do
      raise ArgumentError, "pass :path to a directory for the dataset files"
    end

    path
  end

  defp strategy!(opts) do
    case Keyword.get(opts, :strategy, :containers) do
      strategy when strategy in [:containers, :zip] -> strategy
      _other -> raise ArgumentError, "strategy must be :containers or :zip"
    end
  end

  defp known_strategy(strategy) when strategy in [:containers, :zip], do: :ok
  defp known_strategy(_strategy), do: {:error, %{reason: :invalid_strategy}}
end
