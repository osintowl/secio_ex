defmodule SecioEx.AaerDatabase do
  require SecioEx.Search

  @moduledoc """
  Accounting and Auditing Enforcement Releases.

  `POST https://api.sec-api.io/aaers`

  Results are sorted by `dateTime` descending unless `:sort` is set.
  """

  @sort [%{"dateTime" => %{"order" => "desc"}}]

  @doc """
  Search AAERs with a Lucene query.

  ## Examples

      SecioEx.AaerDatabase.search("tags:\\"accounting fraud\\"", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/aaers", query, opts, size: 50, sort: @sort)
  end

  @doc "Find releases that name a respondent."
  def by_respondent(name, opts \\ []) do
    search(SecioEx.Client.phrase("respondents.name", name), opts)
  end

  @doc "Find releases with a tag, for example `\"accounting fraud\"`."
  def by_tag(tag, opts \\ []) do
    search(SecioEx.Client.phrase("tags", tag), opts)
  end

  SecioEx.Search.pages()
end
