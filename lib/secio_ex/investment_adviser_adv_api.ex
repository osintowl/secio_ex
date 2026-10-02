defmodule SecioEx.InvestmentAdviserAdvApi do
  require SecioEx.Search

  @moduledoc """
  Form ADV firms, individuals, and schedules.

  Firm and individual search is a POST. A schedule is a GET by CRD number.
  """

  @doc """
  Search advisory firms.

  `POST /form-adv/firm`
  """
  def search_firms(query, opts \\ []) when is_binary(query) do
    dataset("/form-adv/firm", query, opts)
  end

  @doc """
  Search advisory individuals.

  `POST /form-adv/individual`
  """
  def search_individuals(query, opts \\ []) when is_binary(query) do
    dataset("/form-adv/individual", query, opts)
  end

  @doc "Walk advisory firms."
  def stream_firms(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> search_firms(query, page) end, opts)
  end

  @doc "Collect advisory firms."
  def all_firms(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> search_firms(query, page) end, opts)
  end

  @doc "Walk advisory individuals."
  def stream_individuals(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> search_individuals(query, page) end, opts)
  end

  @doc "Collect advisory individuals."
  def all_individuals(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> search_individuals(query, page) end, opts)
  end

  @doc "Schedule A direct owners. `GET /form-adv/schedule-a-direct-owners/:crd`"
  def direct_owners(crd, opts \\ []), do: schedule("schedule-a-direct-owners", crd, opts)

  @doc "Schedule B indirect owners. `GET /form-adv/schedule-b-indirect-owners/:crd`"
  def indirect_owners(crd, opts \\ []), do: schedule("schedule-b-indirect-owners", crd, opts)

  @doc "Schedule D section 7.B(1) private funds. `GET /form-adv/schedule-d-7-b-1/:crd`"
  def private_funds(crd, opts \\ []), do: schedule("schedule-d-7-b-1", crd, opts)

  @doc "Schedule D section 1.B other business names. `GET /form-adv/schedule-d-1-b/:crd`"
  def other_business_names(crd, opts \\ []), do: schedule("schedule-d-1-b", crd, opts)

  @doc "Schedule D section 5.K separately managed accounts. `GET /form-adv/schedule-d-5-k/:crd`"
  def separately_managed_accounts(crd, opts \\ []) do
    schedule("schedule-d-5-k", crd, opts)
  end

  @doc "Schedule D section 7.A financial industry affiliations. `GET /form-adv/schedule-d-7-a/:crd`"
  def financial_industry_affiliations(crd, opts \\ []) do
    schedule("schedule-d-7-a", crd, opts)
  end

  @doc "Brochures for a firm. `GET /form-adv/brochures/:crd`"
  def brochures(crd, opts \\ []), do: schedule("brochures", crd, opts)

  defp dataset(path, query, opts) do
    SecioEx.Client.dataset(path, query, opts, size: 50, sort: SecioEx.Client.filed_at_desc())
  end

  defp schedule(name, crd, opts) do
    crd = crd |> to_string() |> String.trim()

    if crd == "" do
      raise ArgumentError, "CRD is empty"
    end

    SecioEx.Client.get("/form-adv/#{name}/#{SecioEx.Client.encode_segment(crd)}", opts)
  end
end
