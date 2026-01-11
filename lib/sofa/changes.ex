defmodule Sofa.Changes do
  @moduledoc """
  CouchDB Changes Feed API.

  The changes feed provides a stream of document changes in a database. This is essential
  for real-time applications, replication, and event-driven architectures.

  ## Modes

  - `:normal` - Returns all changes in a single response (default)
  - `:longpoll` - Waits for changes before returning (long-polling)
  - `:continuous` - Keeps connection open and streams changes as they happen
  - `:eventsource` - Same as continuous but with Server-Sent Events format

  ## Options

  - `:feed` - Feed type (`:normal`, `:longpoll`, `:continuous`, `:eventsource`)
  - `:since` - Start from this sequence number (default: 0)
  - `:limit` - Maximum number of changes to return
  - `:descending` - Return changes in reverse order
  - `:include_docs` - Include full document bodies
  - `:filter` - Filter function name (e.g., "mydesign/myfilter")
  - `:timeout` - Timeout in milliseconds (for longpoll/continuous)
  - `:heartbeat` - Keep connection alive interval in ms
  - `:doc_ids` - Array of document IDs to filter
  - `:style` - `:main_only` (default) or `:all_docs` (include conflicts)
  - `:conflicts` - Include conflict information
  - `:attachments` - Include attachment data
  - `:att_encoding_info` - Include attachment encoding info
  - `:seq_interval` - Interval for emitting sequence numbers

  ## Examples

      # Get all changes
      {:ok, response} = Sofa.Changes.get(sofa, "mydb")
      %{results: results, last_seq: seq} = response.body

      # Get changes since a specific sequence
      {:ok, response} = Sofa.Changes.get(sofa, "mydb", since: "123-xyz")

      # Get changes with documents included
      {:ok, response} = Sofa.Changes.get(sofa, "mydb", include_docs: true)

      # Long-polling (waits for changes)
      {:ok, response} = Sofa.Changes.get(sofa, "mydb",
        feed: :longpoll,
        since: last_seq,
        timeout: 60_000
      )

      # Filter specific documents
      {:ok, response} = Sofa.Changes.get(sofa, "mydb",
        doc_ids: ["user:123", "user:456"]
      )

      # Stream continuous changes
      Sofa.Changes.stream(sofa, "mydb",
        feed: :continuous,
        since: "now",
        include_docs: true
      )
      |> Stream.each(fn change ->
        IO.inspect(change, label: "Change received")
      end)
      |> Stream.run()

  ## Telemetry Events

  - `[:sofa, :changes, :start]` - When changes request starts
  - `[:sofa, :changes, :stop]` - When changes request completes
  - `[:sofa, :changes, :exception]` - When changes request fails
  - `[:sofa, :changes, :change]` - When a change is received (continuous mode)

  """

  alias Sofa.Telemetry

  @type feed_type :: :normal | :longpoll | :continuous | :eventsource
  @type style :: :main_only | :all_docs

  @type option ::
          {:feed, feed_type()}
          | {:since, String.t() | non_neg_integer()}
          | {:limit, pos_integer()}
          | {:descending, boolean()}
          | {:include_docs, boolean()}
          | {:filter, String.t()}
          | {:timeout, timeout()}
          | {:heartbeat, pos_integer()}
          | {:doc_ids, [String.t()]}
          | {:style, style()}
          | {:conflicts, boolean()}
          | {:attachments, boolean()}
          | {:att_encoding_info, boolean()}
          | {:seq_interval, pos_integer()}

  @type change :: %{
          seq: String.t(),
          id: String.t(),
          changes: [%{rev: String.t()}],
          deleted: boolean() | nil,
          doc: map() | nil
        }

  @type changes_response :: %{
          results: [change()],
          last_seq: String.t(),
          pending: non_neg_integer() | nil
        }

  @doc """
  Get changes from a database.

  Returns all changes in the specified feed mode. For `:normal` and `:longpoll`,
  this returns a complete response. For `:continuous`, consider using `stream/3` instead.

  ## Examples

      {:ok, response} = Sofa.Changes.get(sofa, "mydb")

      {:ok, response} = Sofa.Changes.get(sofa, "mydb",
        since: "123-xyz",
        limit: 100,
        include_docs: true
      )

  """
  @spec get(Req.Request.t(), String.t(), [option()]) ::
          {:ok, Sofa.Response.t()} | {:error, Sofa.Error.t()}
  def get(sofa, db_name, opts \\ []) do
    start_time = System.monotonic_time()
    metadata = %{database: db_name, opts: sanitize_opts(opts)}

    Telemetry.span(:changes, metadata, fn ->
      query_params = prepare_changes_opts(opts)

      result =
        sofa
        |> Req.Request.append_request_steps(
          put_path: fn req ->
            %{req | url: URI.append_path(req.url, "/#{db_name}/_changes")}
          end
        )
        |> Req.get(params: query_params)
        |> case do
          {:ok, %Req.Response{status: status, body: body, headers: headers}}
          when status in 200..299 ->
            {:ok, %Sofa.Response{status: status, method: :get, headers: headers, body: body}}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Request failed",
               
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end

      duration = System.monotonic_time() - start_time

      metadata =
        Map.merge(metadata, %{
          duration: duration,
          status: elem(result, 0)
        })

      {result, metadata}
    end)
  end

  @doc """
  Stream changes from a database.

  Returns a `Stream` that emits changes as they arrive. This is particularly useful
  for `:continuous` feeds where changes stream indefinitely.

  ## Examples

      # Stream continuous changes
      Sofa.Changes.stream(sofa, "mydb", feed: :continuous, since: "now")
      |> Stream.each(fn chg ->
        IO.puts("Doc \#{chg.id} changed")
      end)
      |> Stream.run()

      # Process changes with take/take_while
      Sofa.Changes.stream(sofa, "mydb", feed: :continuous)
      |> Stream.take(10)  # Take first 10 changes
      |> Enum.to_list()

      # Handle errors
      Sofa.Changes.stream(sofa, "mydb", feed: :continuous)
      |> Stream.each(fn
        %{error: err_reason} ->
          Logger.error("Change error: \#{inspect(err_reason)}")
        chg ->
          process_change(chg)
      end)
      |> Stream.run()

  """
  @spec stream(Req.Request.t(), String.t(), [option()]) :: Enumerable.t()
  def stream(sofa, db_name, opts \\ []) do
    # Default to continuous feed for streaming
    opts = Keyword.put_new(opts, :feed, :continuous)
    query_params = prepare_changes_opts(opts)

    Stream.resource(
      # Start function - initiate the connection
      fn ->
        url = URI.append_path(sofa.url, "/#{db_name}/_changes")
        full_url = URI.append_query(url, URI.encode_query(query_params))

        # Use Req to create a streaming request
        req =
          sofa
          |> Req.Request.put_header("accept", "application/json")
          |> Req.Request.append_request_steps(
            put_path: fn r ->
              %{r | url: URI.parse(to_string(full_url))}
            end
          )

        # We'll use into: to stream the response
        case Req.get(req, into: :self) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, body, ""}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Request failed"
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end
      end,
      # Next function - emit changes
      fn
        {:ok, body, buffer} ->
          # In continuous mode, body comes as a stream of JSON lines
          # We need to parse each line separately
          case parse_next_change(body, buffer) do
            {:ok, change, new_buffer} ->
              # Emit telemetry event
              Telemetry.event(
                :change,
                %{count: 1},
                %{database: db_name, change: change}
              )

              {[change], {:ok, body, new_buffer}}

            {:incomplete, new_buffer} ->
              # Need more data
              {[], {:ok, body, new_buffer}}
          end

        {:error, _error} = err ->
          {[err], {:done, nil}}

        {:done, _} ->
          {:halt, :done}
      end,
      # After function - cleanup
      fn
        {:ok, _body, _buffer} -> :ok
        {:done, _} -> :ok
        _ -> :ok
      end
    )
  end

  @doc """
  Get changes since the last known sequence.

  This is a convenience function that handles tracking the sequence number
  and fetching only new changes.

  ## Examples

      # Initial fetch
      {:ok, response, new_seq} = Sofa.Changes.since(sofa, "mydb", nil)

      # Subsequent fetches
      {:ok, response, newer_seq} = Sofa.Changes.since(sofa, "mydb", new_seq)

  """
  @spec since(Req.Request.t(), String.t(), String.t() | nil, [option()]) ::
          {:ok, Sofa.Response.t(), String.t()} | {:error, Sofa.Error.t()}
  def since(sofa, db_name, seq \\ nil, opts \\ []) do
    opts =
      if seq do
        Keyword.put(opts, :since, seq)
      else
        opts
      end

    case get(sofa, db_name, opts) do
      {:ok, response} ->
        last_seq = response.body["last_seq"]
        {:ok, response, last_seq}

      {:error, _} = error ->
        error
    end
  end

  ## Private Functions

  @doc false
  def prepare_changes_opts(opts) do
    opts
    |> Enum.reduce(%{}, fn
      {:feed, feed}, acc ->
        Map.put(acc, :feed, Atom.to_string(feed))

      {:since, since}, acc ->
        Map.put(acc, :since, to_string(since))

      {:limit, limit}, acc when is_integer(limit) and limit > 0 ->
        Map.put(acc, :limit, limit)

      {:descending, desc}, acc when is_boolean(desc) ->
        Map.put(acc, :descending, desc)

      {:include_docs, include}, acc when is_boolean(include) ->
        Map.put(acc, :include_docs, include)

      {:filter, filter}, acc when is_binary(filter) ->
        Map.put(acc, :filter, filter)

      {:timeout, timeout}, acc when is_integer(timeout) ->
        Map.put(acc, :timeout, timeout)

      {:heartbeat, heartbeat}, acc when is_integer(heartbeat) and heartbeat > 0 ->
        Map.put(acc, :heartbeat, heartbeat)

      {:doc_ids, doc_ids}, acc when is_list(doc_ids) ->
        # doc_ids must be sent as JSON in the request body for POST
        # For GET, we'll use filter=_doc_ids and send as param
        Map.put(acc, :filter, "_doc_ids")
        |> Map.put(:doc_ids, Jason.encode!(doc_ids))

      {:style, style}, acc when style in [:main_only, :all_docs] ->
        Map.put(acc, :style, Atom.to_string(style))

      {:conflicts, conflicts}, acc when is_boolean(conflicts) ->
        Map.put(acc, :conflicts, conflicts)

      {:attachments, attachments}, acc when is_boolean(attachments) ->
        Map.put(acc, :attachments, attachments)

      {:att_encoding_info, info}, acc when is_boolean(info) ->
        Map.put(acc, :att_encoding_info, info)

      {:seq_interval, interval}, acc when is_integer(interval) and interval > 0 ->
        Map.put(acc, :seq_interval, interval)

      _, acc ->
        acc
    end)
  end

  @doc false
  def parse_next_change(body, buffer) when is_binary(body) do
    # Simple line-based parsing for continuous feed
    # Each change is a JSON object on a single line
    full_data = buffer <> body

    case String.split(full_data, "\n", parts: 2) do
      [line, rest] ->
        case Jason.decode(line) do
          {:ok, change} when is_map(change) ->
            {:ok, parse_change(change), rest}

          {:error, _} ->
            # Incomplete JSON, need more data
            {:incomplete, full_data}
        end

      [incomplete] ->
        # No newline yet, need more data
        {:incomplete, incomplete}
    end
  end

  def parse_next_change(_body, buffer), do: {:incomplete, buffer}

  @doc false
  def parse_change(change) when is_map(change) do
    %{
      seq: change["seq"],
      id: change["id"],
      changes: parse_changes_array(change["changes"]),
      deleted: change["deleted"],
      doc: change["doc"]
    }
  end

  defp parse_changes_array(nil), do: []

  defp parse_changes_array(changes) when is_list(changes) do
    Enum.map(changes, fn c -> %{rev: c["rev"]} end)
  end

  defp sanitize_opts(opts) do
    opts
    |> Keyword.delete(:doc_ids)
    |> Enum.into(%{})
  end
end
