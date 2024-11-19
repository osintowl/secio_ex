defmodule SecioEx do
  @moduledoc """
  A module that connects to and utilizes the sec-api.io API.
  Provides access to Query API, Stream API, and Full-Text Search functionality.

  ## Examples

      # Query API
      {:ok, results} = SecioEx.QueryApi.search("formType:\"10-K\"", api_key: "your_api_key")

      # Full-Text Search
      {:ok, results} = SecioEx.FullTextSearch.search("SpaceX", 
        form_types: ["8-K", "10-Q"],
        api_key: "your_api_key"
      )

      # Stream API
      {:ok, results} = SecioEx.StreamApi.stream(api_key: "your_api_key")
  """
end
