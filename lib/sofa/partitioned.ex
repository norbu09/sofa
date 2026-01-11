defmodule Sofa.Partitioned do
  @moduledoc """
  Support for CouchDB partitioned databases.

  Partitioned databases provide better scalability by co-locating related documents.
  Documents in a partitioned database have IDs in the format `partition:id`.

  ## Benefits

  - Better query performance within a partition
  - Efficient data locality
  - Reduced resource usage for partition-specific queries
  - Horizontal scalability

  ## Usage

      # Create a partitioned database
      {:ok, _} = Sofa.Partitioned.create(conn, "users")

      # Insert a document with partition
      doc = %{name: "Alice", email: "alice@example.com"}
      {:ok, result} = Sofa.Partitioned.put(conn, "users", "org1", "user-123", doc)
      # Creates document with ID "org1:user-123"

      # Get a document
      {:ok, user} = Sofa.Partitioned.get(conn, "users", "org1", "user-123")

      # Query within a partition (efficient!)
      {:ok, results} = Sofa.Partitioned.all_docs(conn, "users", "org1")

      # Mango query within partition
      selector = %{age: %{"$gt" => 18}}
      {:ok, results} = Sofa.Partitioned.find(conn, "users", "org1", selector)

  ## Limitations

  - Document IDs must follow `partition:id` format
  - Partition queries only access documents in that partition
  - Partition names cannot contain colons
  - Global queries (across partitions) are still possible but less efficient

  ## Best Practices

  - Choose partition keys based on your query patterns
  - Keep partitions relatively balanced in size
  - Use partition queries whenever possible
  - Common partition keys: tenant_id, org_id, user_id, region
  """

  alias Sofa.Error

  @type partition :: String.t()
  @type doc_id :: String.t()
  @type partitioned_id :: String.t()

  @doc """
  Creates a partitioned database.

  ## Examples

      {:ok, _} = Sofa.Partitioned.create(conn, "users")
      {:ok, _} = Sofa.Partitioned.create(conn, "users", q: 8)

  ## Options

  - `:q` - Number of shards (default: 8)
  - `:n` - Number of replicas (default: 3)
  """
  @spec create(Sofa.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(conn, database, opts \\ []) do
    query_params = [{:partitioned, true} | opts]

    case Sofa.raw(conn, database, :put, query_params) do
      {:ok, _sofa, resp} -> {:ok, resp.body}
      {:error, resp} -> {:error, Error.from_response(resp.status, resp.body)}
    end
  end

  @doc """
  Checks if a database is partitioned.

  ## Examples

      {:ok, true} = Sofa.Partitioned.partitioned?(conn, "users")
  """
  @spec partitioned?(Sofa.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def partitioned?(conn, database) do
    case Sofa.DB.info(conn, database) do
      {:ok, _sofa, %Sofa.Response{body: body}} ->
        # Check if the props field indicates it's partitioned
        partitioned = get_in(body, ["props", "partitioned"]) || Map.get(body, "partitioned", false)
        {:ok, partitioned}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Builds a partitioned document ID.

  ## Examples

      "org1:user-123" = Sofa.Partitioned.build_id("org1", "user-123")
  """
  @spec build_id(partition(), doc_id()) :: partitioned_id()
  def build_id(partition, id) do
    if String.contains?(partition, ":") do
      raise ArgumentError, "Partition name cannot contain colons: #{partition}"
    end

    "#{partition}:#{id}"
  end

  @doc """
  Parses a partitioned document ID.

  ## Examples

      {"org1", "user-123"} = Sofa.Partitioned.parse_id("org1:user-123")
      :error = Sofa.Partitioned.parse_id("invalid")
  """
  @spec parse_id(partitioned_id()) :: {partition(), doc_id()} | :error
  def parse_id(partitioned_id) do
    case String.split(partitioned_id, ":", parts: 2) do
      [partition, id] -> {partition, id}
      _ -> :error
    end
  end

  @doc """
  Creates or updates a document in a partition.

  ## Examples

      doc = %{name: "Alice", email: "alice@example.com"}
      {:ok, result} = Sofa.Partitioned.put(conn, "users", "org1", "user-123", doc)
  """
  @spec put(Sofa.t(), String.t(), partition(), doc_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def put(conn, database, partition, id, doc, _opts \\ []) do
    partitioned_id = build_id(partition, id)
    path = "#{database}/#{partitioned_id}"
    Sofa.Doc.create(conn, path, Map.put(doc, "_id", partitioned_id))
  end

  @doc """
  Gets a document from a partition.

  ## Examples

      {:ok, user} = Sofa.Partitioned.get(conn, "users", "org1", "user-123")
  """
  @spec get(Sofa.t(), String.t(), partition(), doc_id(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get(conn, database, partition, id, _opts \\ []) do
    partitioned_id = build_id(partition, id)
    path = "#{database}/#{partitioned_id}"
    Sofa.Doc.get(conn, path)
  end

  @doc """
  Deletes a document from a partition.

  ## Examples

      {:ok, _} = Sofa.Partitioned.delete(conn, "users", "org1", "user-123", rev)
  """
  @spec delete(Sofa.t(), String.t(), partition(), doc_id(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def delete(conn, database, partition, id, rev) do
    partitioned_id = build_id(partition, id)
    Sofa.Doc.delete(conn, database, partitioned_id, rev)
  end

  @doc """
  Lists all documents in a partition.

  Much more efficient than querying across all partitions.

  ## Examples

      {:ok, result} = Sofa.Partitioned.all_docs(conn, "users", "org1")
      {:ok, result} = Sofa.Partitioned.all_docs(conn, "users", "org1", include_docs: true, limit: 10)

  ## Options

  All standard view options are supported.
  """
  @spec all_docs(Sofa.t(), String.t(), partition(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def all_docs(conn, database, partition, opts \\ []) do
    path = "/#{database}/_partition/#{partition}/_all_docs"
    Sofa.get(conn, path, opts)
  end

  @doc """
  Queries a view within a partition.

  ## Examples

      {:ok, results} = Sofa.Partitioned.view(conn, "users", "org1", "by_email", "index")
      {:ok, results} = Sofa.Partitioned.view(conn, "users", "org1", "by_email", "index",
                                               key: "alice@example.com")

  ## Options

  All standard view options are supported.
  """
  @spec view(Sofa.t(), String.t(), partition(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def view(conn, database, partition, design_doc, view_name, opts \\ []) do
    path = "/#{database}/_partition/#{partition}/_design/#{design_doc}/_view/#{view_name}"
    Sofa.get(conn, path, opts)
  end

  @doc """
  Queries documents in a partition using Mango.

  Partition queries are much more efficient than global queries.

  ## Examples

      selector = %{age: %{"$gt" => 18}, active: true}
      {:ok, results} = Sofa.Partitioned.find(conn, "users", "org1", selector)
      {:ok, results} = Sofa.Partitioned.find(conn, "users", "org1", selector, limit: 10)

  ## Options

  All Mango query options are supported.
  """
  @spec find(Sofa.t(), String.t(), partition(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def find(conn, database, partition, selector, opts \\ []) do
    path = "/#{database}/_partition/#{partition}/_find"
    query = Map.merge(%{selector: selector}, Map.new(opts))

    case Sofa.post(conn, path, query) do
      {:ok, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      error ->
        error
    end
  end

  @doc """
  Explains a query execution plan within a partition.

  Useful for optimizing partition queries.

  ## Examples

      selector = %{age: %{"$gt" => 18}}
      {:ok, plan} = Sofa.Partitioned.explain(conn, "users", "org1", selector)
  """
  @spec explain(Sofa.t(), String.t(), partition(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def explain(conn, database, partition, selector, opts \\ []) do
    path = "/#{database}/_partition/#{partition}/_explain"
    query = Map.merge(%{selector: selector}, Map.new(opts))

    case Sofa.post(conn, path, query) do
      {:ok, %Sofa.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Sofa.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      error ->
        error
    end
  end

  @doc """
  Gets partition information and statistics.

  ## Examples

      {:ok, stats} = Sofa.Partitioned.info(conn, "users", "org1")
      # Returns: %{
      #   "doc_count" => 150,
      #   "doc_del_count" => 5,
      #   "partition" => "org1",
      #   "sizes" => %{...}
      # }
  """
  @spec info(Sofa.t(), String.t(), partition()) :: {:ok, map()} | {:error, term()}
  def info(conn, database, partition) do
    path = "/#{database}/_partition/#{partition}"
    Sofa.get(conn, path, [])
  end
end
