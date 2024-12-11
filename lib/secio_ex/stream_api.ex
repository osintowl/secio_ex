defmodule SecioEx.StreamApi do
  @moduledoc """
  A WebSocket client for streaming SEC (Securities and Exchange Commission) filing data
  in real-time using the sec-api.io service.

  ## Example Usage

      # Define a custom callback to process 8-K filings
      custom_callback = fn
        [%{"formType" => form_type, "entities" => entities, "linkToTxt" => link_to_txt}]
            when form_type in ["8-K", "8-K/A"] ->
          IO.puts("Entities: \#{inspect(entities)}")
          IO.puts("Form Type: \#{form_type}")
          IO.puts("Link to HTML: \#{link_to_txt}\\n\\n")

        _ ->
          IO.puts("Form type not matched or unexpected data structure\\n ")
      end

      # Start the WebSocket connection
      {:ok, pid} = SecioEx.StreamApi.sec_stream("your_api_key_here", custom_callback)
  """

  use WebSockex

  @websocket_url "wss://stream.sec-api.io?apiKey="

  @doc """
  Establishes a WebSocket connection to the SEC API streaming service.

  ## Parameters

    * `api_key` - Your SEC API authentication key
    * `callback` - Optional function to process incoming messages. Defaults to `default_callback/1`

  ## Returns

    * `{:ok, pid}` - On successful connection
    * `{:error, term}` - On failure

  ## Example

      SecioEx.StreamApi.sec_stream("your_api_key_here")
      SecioEx.StreamApi.sec_stream("your_api_key_here", &MyModule.process_filing/1)
  """
  def sec_stream(api_key, callback \\ &default_callback/1) do
    url = "#{@websocket_url}" <> api_key
    WebSockex.start_link(url, __MODULE__, callback)
  end

  @doc """
  Internal callback that handles incoming WebSocket messages.
  Decodes JSON messages and passes them to the specified callback function.

  ## Parameters

    * `{:text, msg}` - Tuple containing the received WebSocket frame
    * `state` - Current callback function

  ## Returns

    * `{:ok, state}` - Tuple indicating successful message processing
  """
  def handle_frame({:text, msg}, state) do
    decoded_msg = Jason.decode!(msg)
    state.(decoded_msg)
    {:ok, state}
  end

  @doc false
  defp default_callback(msg) do
    IO.puts("#{inspect(msg)}")
  end
end
