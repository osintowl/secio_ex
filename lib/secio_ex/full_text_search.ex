defmodule SecioEx.FullTextSearch do
  @fulltext_url "https://api.sec-api.io/full-text-search"

  @moduledoc """
  A way to do a Full text search of SEC filings and get back a list of them. 
  """

  @doc """
  Performs a full-text search across SEC EDGAR filings.

  ## Parameters
    - query: String containing the search term or phrase
    - opts: Keyword list of options
      - form_types: List of form types to search (e.g., ["8-K", "10-K"])
      - start_date: Start date in "YYYY-MM-DD" format
      - end_date: End date in "YYYY-MM-DD" format
      - ciks: List of CIK numbers to search
      - page: Page number for pagination (default: 1)
      - api_key: Your SEC API key

  ## Examples
      iex> SecioEx.FullTextSearch.search("SpaceX", 
        form_types: ["8-K", "10-Q"],
        start_date: "2024-01-01",
        end_date: "2024-03-31",
        api_key: "your_api_key"
      )
      {:ok, %{total: %{value: 86, relation: "eq"}, filings: [...]}}

      # Search with exact phrase
      iex> SecioEx.FullTextSearch.search("\"substantial doubt\"",
        form_types: ["10-K"],
        api_key: "your_api_key"
      )
  """
  def search(query, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)

    payload =
      %{
        "query" => query
      }
      |> maybe_add_form_types(Keyword.get(opts, :form_types))
      |> maybe_add_dates(
        Keyword.get(opts, :start_date),
        Keyword.get(opts, :end_date)
      )
      |> maybe_add_ciks(Keyword.get(opts, :ciks))
      |> maybe_add_page(Keyword.get(opts, :page))

    Req.post(@fulltext_url,
      json: payload,
      headers: [{"Authorization", api_key}]
    )
    |> handle_response()
  end

  @doc """
  Helper function to search for an exact phrase.

  ## Examples
      iex> SecioEx.FullTextSearch.search_exact_phrase("substantial doubt",
        api_key: "your_api_key"
      )
  """
  def search_exact_phrase(phrase, opts \\ []) do
    search(~s("#{phrase}"), opts)
  end

  @doc """
  Helper function to search with wildcards.

  ## Examples
      iex> SecioEx.FullTextSearch.search_wildcard("gas",
        api_key: "your_api_key"
      )
  """
  def search_wildcard(term, opts \\ []) do
    search("#{term}*", opts)
  end

  @doc """
  Helper function to search with multiple terms using OR.

  ## Examples
      iex> SecioEx.FullTextSearch.search_any_of(["qualified opinion", "except for"],
        api_key: "your_api_key"
      )
  """
  def search_any_of(terms, opts \\ []) when is_list(terms) do
    query =
      terms
      |> Enum.map(&~s("#{&1}"))
      |> Enum.join(" OR ")

    search(query, opts)
  end

  # Private Functions

  defp maybe_add_form_types(payload, nil), do: payload

  defp maybe_add_form_types(payload, form_types) when is_list(form_types) do
    Map.put(payload, "formTypes", form_types)
  end

  defp maybe_add_dates(payload, nil, nil), do: payload

  defp maybe_add_dates(payload, start_date, end_date) do
    payload
    |> maybe_put("startDate", start_date)
    |> maybe_put("endDate", end_date)
  end

  defp maybe_add_ciks(payload, nil), do: payload

  defp maybe_add_ciks(payload, ciks) when is_list(ciks) do
    Map.put(payload, "ciks", ciks)
  end

  defp maybe_add_page(payload, nil), do: payload

  defp maybe_add_page(payload, page) when is_integer(page) do
    Map.put(payload, "page", to_string(page))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status_code: status, body: body}}
  end

  defp handle_response({:error, error}) do
    {:error, error}
  end
end
