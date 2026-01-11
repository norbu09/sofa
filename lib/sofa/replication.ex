defmodule Sofa.Replication do
  @moduledoc """
  CouchDB replication management.

  Replication allows you to synchronize databases, either:
  - Between two CouchDB servers
  - Between a server and a local database
  - Continuously or one-time

  ## Features

  - One-time and continuous replication
  - Filtered replication
  - Replication scheduling
  - Replication monitoring
  - Conflict handling

  ## Usage

      # One-time replication
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "http://server1:5984/db",
        target: "http://server2:5984/db"
      )

      # Continuous replication
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "source_db",
        target: "target_db",
        continuous: true,
        create_target: true
      )

      # Filtered replication
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "source_db",
        target: "target_db",
        filter: "mydesign/myfilter",
        query_params: %{status: "active"}
      )

      # Check replication status
      {:ok, status} = Sofa.Replication.status(conn, replication_id)

      # Cancel replication
      :ok = Sofa.Replication.cancel(conn, replication_id)

  ## Replication Scheduler

  CouchDB 2.0+ uses a replication scheduler for better management:

      # List all replications
      {:ok, replications} = Sofa.Replication.list(conn)

      # Get scheduler jobs
      {:ok, jobs} = Sofa.Replication.jobs(conn)

      # Get scheduler docs
      {:ok, docs} = Sofa.Replication.docs(conn)
  """

  alias Sofa.Error

  @type replication_id :: String.t()
  @type replication_opts :: keyword()

  @doc """
  Starts a replication.

  ## Options

  Required:
  - `:source` - Source database URL or name
  - `:target` - Target database URL or name

  Optional:
  - `:continuous` - Boolean, continuous replication (default: false)
  - `:create_target` - Boolean, create target if doesn't exist (default: false)
  - `:filter` - Filter function (format: "designdoc/filtername")
  - `:query_params` - Parameters for filter function
  - `:doc_ids` - List of document IDs to replicate
  - `:selector` - Mango selector for filtering
  - `:checkpoint_interval` - Milliseconds between checkpoints
  - `:connection_timeout` - Connection timeout in milliseconds
  - `:retries_per_request` - Number of retries per request
  - `:http_connections` - Maximum number of HTTP connections
  - `:worker_processes` - Number of worker processes
  - `:worker_batch_size` - Batch size for workers
  - `:use_checkpoints` - Boolean, use checkpoints (default: true)
  - `:source_proxy` - Proxy URL for source
  - `:target_proxy` - Proxy URL for target

  ## Examples

      # Basic replication
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "db1",
        target: "db2"
      )

      # Continuous with filter
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "db1",
        target: "db2",
        continuous: true,
        filter: "mydesign/active_only",
        query_params: %{status: "active"}
      )

      # Selective replication
      {:ok, result} = Sofa.Replication.replicate(conn,
        source: "db1",
        target: "db2",
        doc_ids: ["doc1", "doc2", "doc3"]
      )
  """
  @spec replicate(Sofa.t(), replication_opts()) :: {:ok, map()} | {:error, term()}
  def replicate(conn, opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)

    replication_doc =
      %{
        source: expand_db_url(source),
        target: expand_db_url(target)
      }
      |> add_if_present(opts, :continuous)
      |> add_if_present(opts, :create_target)
      |> add_if_present(opts, :filter)
      |> add_if_present(opts, :query_params)
      |> add_if_present(opts, :doc_ids)
      |> add_if_present(opts, :selector)
      |> add_if_present(opts, :checkpoint_interval)
      |> add_if_present(opts, :connection_timeout)
      |> add_if_present(opts, :retries_per_request)
      |> add_if_present(opts, :http_connections)
      |> add_if_present(opts, :worker_processes)
      |> add_if_present(opts, :worker_batch_size)
      |> add_if_present(opts, :use_checkpoints)
      |> add_if_present(opts, :source_proxy)
      |> add_if_present(opts, :target_proxy)

    case Sofa.post(conn, "/_replicate", replication_doc) do
      {:ok, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      error ->
        error
    end
  end

  @doc """
  Creates a replication document in the _replicator database.

  This is the preferred method for persistent replications.

  ## Examples

      {:ok, result} = Sofa.Replication.create_doc(conn, "my-replication",
        source: "db1",
        target: "db2",
        continuous: true
      )
  """
  @spec create_doc(Sofa.t(), replication_id(), replication_opts()) ::
          {:ok, map()} | {:error, term()}
  def create_doc(conn, replication_id, opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)

    replication_doc =
      %{
        _id: replication_id,
        source: expand_db_url(source),
        target: expand_db_url(target)
      }
      |> add_if_present(opts, :continuous)
      |> add_if_present(opts, :create_target)
      |> add_if_present(opts, :filter)
      |> add_if_present(opts, :query_params)
      |> add_if_present(opts, :doc_ids)
      |> add_if_present(opts, :selector)

    Sofa.Doc.create(conn, "_replicator", replication_doc)
  end

  @doc """
  Gets a replication document from _replicator database.

  ## Examples

      {:ok, replication} = Sofa.Replication.get_doc(conn, "my-replication")
  """
  @spec get_doc(Sofa.t(), replication_id()) :: {:ok, map()} | {:error, term()}
  def get_doc(conn, replication_id) do
    path = "_replicator/#{replication_id}"
    Sofa.Doc.get(conn, path)
  end

  @doc """
  Deletes a replication document (cancels replication).

  ## Examples

      {:ok, replication} = Sofa.Replication.get_doc(conn, "my-replication")
      :ok = Sofa.Replication.delete_doc(conn, "my-replication", replication["_rev"])
  """
  @spec delete_doc(Sofa.t(), replication_id(), String.t()) :: :ok | {:error, term()}
  def delete_doc(conn, replication_id, rev) do
    case Sofa.Doc.delete(conn, "_replicator", replication_id, rev) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Cancels a replication started with replicate/2.

  ## Examples

      # Start replication
      {:ok, %{"_local_id" => id}} = Sofa.Replication.replicate(conn,
        source: "db1",
        target: "db2",
        continuous: true
      )

      # Cancel it
      :ok = Sofa.Replication.cancel(conn, id)
  """
  @spec cancel(Sofa.t(), replication_id()) :: :ok | {:error, term()}
  def cancel(conn, replication_id) do
    case Sofa.post(conn, "/_replicate", %{replication_id: replication_id, cancel: true}) do
      {:ok, %Sofa.Response{status: 200}} -> :ok
      {:ok, %Sofa.Response{status: status, body: body}} -> {:error, Error.from_response(status, body)}
      error -> error
    end
  end

  @doc """
  Lists all replications from _replicator database.

  ## Examples

      {:ok, replications} = Sofa.Replication.list(conn)
  """
  @spec list(Sofa.t()) :: {:ok, [map()]} | {:error, term()}
  def list(conn) do
    case Sofa.DB.all_docs(conn, "_replicator", include_docs: true) do
      {:ok, %{rows: rows}} ->
        docs = Enum.map(rows, fn %{doc: doc} -> doc end)
        {:ok, docs}

      error ->
        error
    end
  end

  @doc """
  Gets the status of a replication.

  ## Examples

      {:ok, status} = Sofa.Replication.status(conn, "my-replication")
  """
  @spec status(Sofa.t(), replication_id()) :: {:ok, map()} | {:error, term()}
  def status(conn, replication_id) do
    get_doc(conn, replication_id)
  end

  @doc """
  Gets replication scheduler jobs (active replications).

  Returns information about currently running replications.

  ## Examples

      {:ok, %{jobs: jobs}} = Sofa.Replication.jobs(conn)
  """
  @spec jobs(Sofa.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def jobs(conn, opts \\ []) do
    case Sofa.get(conn, "/_scheduler/jobs", opts) do
      {:ok, _sofa, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, _sofa, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets replication scheduler docs (replication documents).

  Returns information about replication documents in _replicator database.

  ## Examples

      {:ok, %{docs: docs}} = Sofa.Replication.docs(conn)
  """
  @spec docs(Sofa.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def docs(conn, opts \\ []) do
    case Sofa.get(conn, "/_scheduler/docs", opts) do
      {:ok, _sofa, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, _sofa, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets replication scheduler document for a specific database.

  ## Examples

      {:ok, %{docs: docs}} = Sofa.Replication.docs(conn, "_replicator")
  """
  @spec docs(Sofa.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def docs(conn, database, opts) do
    case Sofa.get(conn, "/_scheduler/docs/#{database}", opts) do
      {:ok, _sofa, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, _sofa, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets detailed information about a specific replication.

  ## Examples

      {:ok, info} = Sofa.Replication.doc_info(conn, "_replicator", "my-replication")
  """
  @spec doc_info(Sofa.t(), String.t(), replication_id()) :: {:ok, map()} | {:error, term()}
  def doc_info(conn, database, replication_id) do
    case Sofa.get(conn, "/_scheduler/docs/#{database}/#{replication_id}", []) do
      {:ok, _sofa, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, _sofa, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, _} = error ->
        error
    end
  end

  # Private Functions

  defp expand_db_url(url) when is_binary(url) do
    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
      url
    else
      # Local database name
      url
    end
  end

  defp add_if_present(map, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end
end
