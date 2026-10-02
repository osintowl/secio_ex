defmodule SecioEx.FormD do
  require SecioEx.Search

  @moduledoc """
  Form D exempt offerings.

  `POST https://api.sec-api.io/form-d`
  """

  @doc """
  Search Form D filings.

  ## Examples

      SecioEx.FormD.search(
        "offeringData.industryGroup.investmentFundInfo.investmentFundType:\\"Hedge Fund\\"",
        api_key: "your_api_key"
      )
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-d", query, opts, size: 50, sort: SecioEx.Client.filed_at_desc())
  end

  @doc "Offerings whose primary issuer name matches."
  def by_issuer(name, opts \\ []) do
    search(SecioEx.Client.phrase("primaryIssuer.entityName", name), opts)
  end

  SecioEx.Search.pages()
end
