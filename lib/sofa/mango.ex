defmodule Sofa.Mango do
  @moduledoc """
  CouchDB Mango Query API (Cloudant Query / _find endpoint).

  Mango provides a declarative JSON query language for CouchDB, similar to MongoDB's
  query syntax. It's the modern way to query CouchDB without writing map/reduce views.

  ## Query Syntax

  Queries are expressed as JSON objects with selector expressions:

      %{
        "selector" => %{
          "type" => "user",
          "age" => %{"$gt" => 21}
        },
        "fields" => ["_id", "name", "email"],
        "sort" => [%{"name" => "asc"}],
        "limit" => 10
      }

  ## Operators

  ### Combination Operators
  - `$and` - Match all conditions
  - `$or` - Match any condition
  - `$not` - Negate a condition
  - `$nor` - None of the conditions match
  - `$all` - Array contains all values

  ### Condition Operators
  - `$lt` - Less than
  - `$lte` - Less than or equal
  - `$gt` - Greater than
  - `$gte` - Greater than or equal
  - `$eq` - Equal to (default)
  - `$ne` - Not equal to
  - `$exists` - Field exists
  - `$type` - Field type matches
  - `$in` - Value in array
  - `$nin` - Value not in array
  - `$size` - Array size
  - `$mod` - Modulo operation
  - `$regex` - Regular expression match

  ## Examples

      # Simple query
      {:ok, result} = Sofa.Mango.find(sofa, "mydb", %{
        "selector" => %{"type" => "user"}
      })

      # Complex query with operators
      {:ok, result} = Sofa.Mango.find(sofa, "mydb", %{
        "selector" => %{
          "$and" => [
            %{"type" => "user"},
            %{"age" => %{"$gte" => 18}},
            %{"status" => %{"$ne" => "deleted"}}
          ]
        },
        "fields" => ["_id", "name", "email", "age"],
        "sort" => [%{"age" => "desc"}, %{"name" => "asc"}],
        "limit" => 50,
        "skip" => 0
      })

      # Query with index hint
      {:ok, result} = Sofa.Mango.find(sofa, "mydb", %{
        "selector" => %{"email" => "user@example.com"},
        "use_index" => "_design/idx-email"
      })

      # Create an index
      {:ok, _} = Sofa.Mango.create_index(sofa, "mydb", %{
        "index" => %{
          "fields" => ["type", "age"]
        },
        "name" => "idx-type-age",
        "type" => "json"
      })

      # List indexes
      {:ok, indexes} = Sofa.Mango.list_indexes(sofa, "mydb")

      # Explain query (shows which index will be used)
      {:ok, plan} = Sofa.Mango.explain(sofa, "mydb", %{
        "selector" => %{"type" => "user", "age" => %{"$gt" => 21}}
      })

  ## Telemetry Events

  - `[:sofa, :mango, :find, :start]` - When find query starts
  - `[:sofa, :mango, :find, :stop]` - When find query completes
  - `[:sofa, :mango, :find, :exception]` - When find query fails

  """

  alias Sofa.Telemetry

  @type selector :: map()
  @type query :: %{
          required(String.t()) => selector(),
          optional(String.t()) => any()
        }

  @type find_result :: %{
          docs: [map()],
          bookmark: String.t() | nil,
          warning: String.t() | nil,
          execution_stats: map() | nil
        }

  @doc """
  Execute a Mango query to find documents.

  ## Query Fields

  - `selector` (required) - JSON object describing criteria for selecting documents
  - `fields` - Array of field names to include in results (default: all fields)
  - `sort` - Array of sort specifications (e.g., `[%{"age" => "desc"}]`)
  - `limit` - Maximum number of documents to return (default: 25)
  - `skip` - Number of documents to skip (for pagination)
  - `use_index` - Specific index to use (design doc name or `[design_doc, index_name]`)
  - `bookmark` - Bookmark for pagination (from previous query result)
  - `update` - Whether to update the index before query (default: true)
  - `stable` - Use stable set of shards for query (default: false)
  - `execution_stats` - Include execution statistics (default: false)

  ## Examples

      # Basic find
      {:ok, result} = Sofa.Mango.find(sofa, "users", %{
        "selector" => %{"type" => "admin"}
      })

      result.docs
      #=> [%{"_id" => "user:1", "type" => "admin", ...}, ...]

      # Pagination with bookmark
      {:ok, page1} = Sofa.Mango.find(sofa, "users", %{
        "selector" => %{"type" => "user"},
        "limit" => 10
      })

      {:ok, page2} = Sofa.Mango.find(sofa, "users", %{
        "selector" => %{"type" => "user"},
        "limit" => 10,
        "bookmark" => page1.bookmark
      })

  """
  @spec find(Req.Request.t(), String.t(), query()) ::
          {:ok, find_result()} | {:error, Sofa.Error.t()}
  def find(sofa, db_name, query) when is_map(query) do
    Telemetry.span([:mango, :find], %{database: db_name, query: sanitize_query(query)}, fn ->
      result =
        sofa
        |> Req.Request.append_request_steps(
          put_path: fn req ->
            %{req | url: URI.append_path(req.url, "/#{db_name}/_find")}
          end
        )
        |> Req.post(json: query)
        |> case do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok,
             %{
               docs: body["docs"] || [],
               bookmark: body["bookmark"],
               warning: body["warning"],
               execution_stats: body["execution_stats"]
             }}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Query failed",
               
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end

      {result, %{status: elem(result, 0)}}
    end)
  end

  @doc """
  Explain a Mango query without executing it.

  This returns the query execution plan, including which index will be used
  and other optimization information. Useful for debugging slow queries.

  ## Examples

      {:ok, plan} = Sofa.Mango.explain(sofa, "users", %{
        "selector" => %{"age" => %{"$gt" => 21}}
      })

      IO.inspect(plan.index, label: "Index used")
      IO.inspect(plan.covering, label: "Covering index?")

  """
  @spec explain(Req.Request.t(), String.t(), query()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def explain(sofa, db_name, query) when is_map(query) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{req | url: URI.append_path(req.url, "/#{db_name}/_explain")}
      end
    )
    |> Req.post(json: query)
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Explain failed",
           
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  Create a Mango index.

  Indexes improve query performance by allowing CouchDB to efficiently locate
  matching documents without scanning the entire database.

  ## Index Definition

  - `index.fields` (required) - Array of field names or field/sort pairs
  - `name` - Index name (auto-generated if not provided)
  - `type` - Index type: "json" (default) or "text" (for full-text search)
  - `ddoc` - Design document name (auto-generated if not provided)
  - `partial_filter_selector` - Only index documents matching this selector

  ## Examples

      # Simple index
      {:ok, result} = Sofa.Mango.create_index(sofa, "users", %{
        "index" => %{
          "fields" => ["email"]
        }
      })

      # Named index with multiple fields
      {:ok, result} = Sofa.Mango.create_index(sofa, "users", %{
        "index" => %{
          "fields" => ["type", "created_at"]
        },
        "name" => "idx-type-created",
        "ddoc" => "indexes"
      })

      # Partial index
      {:ok, result} = Sofa.Mango.create_index(sofa, "users", %{
        "index" => %{
          "fields" => ["age"]
        },
        "partial_filter_selector" => %{
          "type" => "user"
        }
      })

      # Text index for full-text search
      {:ok, result} = Sofa.Mango.create_index(sofa, "posts", %{
        "index" => %{
          "fields" => [%{"name" => "title", "type" => "string"}]
        },
        "name" => "text-search",
        "type" => "text"
      })

  """
  @spec create_index(Req.Request.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def create_index(sofa, db_name, index_def) when is_map(index_def) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{req | url: URI.append_path(req.url, "/#{db_name}/_index")}
      end
    )
    |> Req.post(json: index_def)
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Index creation failed",
           
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  List all Mango indexes in a database.

  ## Examples

      {:ok, result} = Sofa.Mango.list_indexes(sofa, "users")

      result["indexes"]
      |> Enum.each(fn idx ->
        IO.puts("Index: \#{idx["name"]} - Fields: \#{inspect(idx["def"]["fields"])}")
      end)

  """
  @spec list_indexes(Req.Request.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def list_indexes(sofa, db_name) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{req | url: URI.append_path(req.url, "/#{db_name}/_index")}
      end
    )
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "List indexes failed",
           
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  Delete a Mango index.

  ## Examples

      {:ok, _} = Sofa.Mango.delete_index(sofa, "users", "idx-email")

      # Delete with design doc specified
      {:ok, _} = Sofa.Mango.delete_index(sofa, "users", "indexes", "idx-type-age")

  """
  @spec delete_index(Req.Request.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def delete_index(sofa, db_name, ddoc, index_name) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{
          req
          | url: URI.append_path(req.url, "/#{db_name}/_index/#{ddoc}/json/#{index_name}")
        }
      end
    )
    |> Req.delete()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Delete index failed",
           
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  Delete a Mango index by name (when design doc is unknown).

  This will first list all indexes to find the design doc, then delete the index.

  ## Examples

      {:ok, _} = Sofa.Mango.delete_index(sofa, "users", "idx-email")

  """
  @spec delete_index(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def delete_index(sofa, db_name, index_name) do
    with {:ok, %{"indexes" => indexes}} <- list_indexes(sofa, db_name),
         %{"ddoc" => ddoc} <- Enum.find(indexes, fn idx -> idx["name"] == index_name end) do
      # Extract design doc name (remove _design/ prefix)
      ddoc_name = String.replace_prefix(ddoc, "_design/", "")
      delete_index(sofa, db_name, ddoc_name, index_name)
    else
      nil ->
        {:error,
         %Sofa.Error.NotFound{
           reason: "Index '#{index_name}' not found in database '#{db_name}'"
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Execute a Mango query with optional query parameters (4-parameter version).

  This is a convenience wrapper around `find/3` that accepts a selector map
  and options separately, then combines them into a single query.

  ## Examples

      selector = %{"type" => "user", "age" => %{"$gt" => 21}}
      opts = [limit: 10, sort: [%{"name" => "asc"}]]
      {:ok, result} = Sofa.Mango.query(sofa, "users", selector, opts)

  """
  @spec query(Req.Request.t(), String.t(), map(), keyword()) ::
          {:ok, find_result()} | {:error, Sofa.Error.t()}
  def query(sofa, database, selector, opts \\ []) do
    query_map =
      opts
      |> Enum.into(%{})
      |> Map.put("selector", selector)
      |> convert_keys_to_strings()

    find(sofa, database, query_map)
  end

  ## Helper Functions

  defp sanitize_query(query) do
    # Remove sensitive data from query for logging
    Map.drop(query, ["fields", "selector"])
    |> Map.put("selector_keys", query["selector"] |> Map.keys())
  end

  defp convert_keys_to_strings(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), convert_keys_to_strings(v)}
      {k, v} -> {k, convert_keys_to_strings(v)}
    end)
    |> Enum.into(%{})
  end

  defp convert_keys_to_strings(list) when is_list(list) do
    Enum.map(list, &convert_keys_to_strings/1)
  end

  defp convert_keys_to_strings(value), do: value
end
