defmodule Sofa.View do
  require Logger

  @moduledoc """
  Documentation for `Sofa.View`, a test-driven idiomatic Apache CouchDB client.

  > If the only tool you have is CouchDB, then
  > everything looks like {:ok, :relax}

  ## Examples

  iex> Sofa.View.new()

  """

  defstruct rows: [],
            total_rows: 0,
            offset: 0

  @type t :: %__MODULE__{
          rows: List.t(),
          total_rows: number,
          offset: number
        }

  @spec from_map(map()) :: %Sofa.View{}
  def from_map(%Sofa.Response{body: body}) do
    Logger.debug("Response: #{inspect(body)}")

    case Enum.map(body["rows"], fn x -> %{x["key"] => parse_row(x["value"])} end) do
      [%{nil: val}] ->
        %Sofa.View{
          rows: [val]
        }

      rows ->
        %Sofa.View{
          rows: rows,
          total_rows: body["total_rows"],
          offset: body["offset"]
        }
    end
  end

  @spec from_map(map(), :include_docs) :: %Sofa.View{}
  def from_map(%Sofa.Response{body: body}, :include_docs) do
    Logger.debug("Response: #{inspect(body)}")

    case Enum.map(body["rows"], fn x -> parse_doc_row(x) end) do
      [%{nil: val}] ->
        %Sofa.View{
          rows: [val]
        }

      rows ->
        %Sofa.View{
          rows: rows,
          total_rows: body["total_rows"],
          offset: body["offset"]
        }
    end
  end

  @spec info(Sofa.t(), String.t()) :: {:error, any()} | {:ok, Sofa.t(), any()}
  def info(sofa = %Sofa{database: db}, raw_path) when is_binary(raw_path) do
    path =
      case String.split(raw_path, "/", parts: 2) do
        [ddoc, view] ->
          "#{db}/_design/#{ddoc}/_view/#{view}"

        [ddoc] ->
          "#{db}/_design/#{ddoc}"
      end

    case Sofa.raw(sofa, path, :head) do
      {:error, reason} ->
        {:error, reason}

      {:ok, sofa, resp} ->
        {:ok, %Sofa{sofa | database: db},
         %Sofa.Response{
           body: resp.body,
           url: resp.url,
           query: resp.query,
           method: resp.method,
           headers: resp.headers,
           status: resp.status
         }}
    end
  end

  @doc """
  Query a CouchDB view with comprehensive options.

  ## Options

  ### Selection and Filtering
  - `:key` - Return only documents with the specified key
  - `:keys` - Return only documents with the specified keys (POST request)
  - `:startkey` - Return records starting with the specified key
  - `:endkey` - Stop returning records when the specified key is reached
  - `:startkey_docid` - Return records starting with the specified document ID (with startkey)
  - `:endkey_docid` - Stop returning records when the specified document ID is reached (with endkey)

  ### Pagination and Limits
  - `:limit` - Limit the number of documents in the output
  - `:skip` - Skip n number of documents
  - `:descending` - Return documents in descending order (default: false)

  ### Value Processing
  - `:include_docs` - Include the full document body (default: false)
  - `:inclusive_end` - Include endkey in results (default: true)
  - `:group` - Group results using the reduce function
  - `:group_level` - Specify the group level to be used
  - `:reduce` - Use the reduce function (default: true if defined)

  ### Performance
  - `:update_seq` - Include update_seq in the response (default: false)
  - `:stale` - Allow stale views (:ok or :update_after)

  ## Examples

      # Get all documents with a specific key
      Sofa.View.get(sofa, "mydesign/myview", key: "some_key")

      # Paginate results
      Sofa.View.get(sofa, "mydesign/myview", limit: 10, skip: 20)

      # Get a range of keys
      Sofa.View.get(sofa, "mydesign/myview",
        startkey: "2024-01-01",
        endkey: "2024-12-31"
      )

      # Descending order with docs included
      Sofa.View.get(sofa, "mydesign/myview",
        descending: true,
        include_docs: true
      )
  """
  @spec get(Sofa.t(), String.t(), Keyword.t()) :: {:error, any()} | {:ok, Sofa.View.t()}
  def get(sofa = %Sofa{database: db}, raw_path, opts \\ []) when is_binary(raw_path) do
    case String.split(raw_path, "/", parts: 2) do
      [ddoc, view] ->
        path = "#{db}/_design/#{ddoc}/_view/#{view}"

        case call(sofa, :get, path, prepare_view_opts(opts)) do
          {:ok, resp} ->
            case Keyword.get(opts, :include_docs, false) do
              true ->
                {:ok, from_map(resp, :include_docs)}

              _ ->
                {:ok, from_map(resp)}
            end

          error ->
            error
        end

      [ddoc] ->
        path = "#{db}/_design/#{ddoc}"
        call(sofa, :get, path, prepare_view_opts(opts))
    end
  end

  @doc """
  Get all documents in a database with optional filtering and pagination.

  Supports all the same options as `get/3`.

  ## Examples

      # Get all docs with pagination
      Sofa.View.all_docs(sofa, limit: 100, skip: 0)

      # Get all docs in descending order with full documents
      Sofa.View.all_docs(sofa, descending: true, include_docs: true)

      # Get a range of document IDs
      Sofa.View.all_docs(sofa,
        startkey: "doc_2024",
        endkey: "doc_2024\ufff0"
      )
  """
  @spec all_docs(Sofa.t(), Keyword.t()) :: {:error, any()} | {:ok, Sofa.View.t()}
  def all_docs(sofa = %Sofa{database: db}, opts \\ []) do
    path = "#{db}/_all_docs"

    case call(sofa, :get, path, prepare_view_opts(opts)) do
      {:ok, resp} ->
        {:ok, from_map(resp, :include_docs)}

      error ->
        error
    end
  end

  defp call(sofa, method, path, opts) do
    case Sofa.raw(sofa, path, method, opts) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, resp}
    end
  end

  @doc false
  @spec prepare_view_opts(Keyword.t()) :: Keyword.t()
  def prepare_view_opts(opts) do
    # CouchDB view options that need special handling
    opts
    |> Enum.map(fn
      # Boolean options
      {:include_docs, val} when is_boolean(val) -> {:include_docs, val}
      {:descending, val} when is_boolean(val) -> {:descending, val}
      {:reduce, val} when is_boolean(val) -> {:reduce, val}
      {:group, val} when is_boolean(val) -> {:group, val}
      {:inclusive_end, val} when is_boolean(val) -> {:inclusive_end, val}
      {:update_seq, val} when is_boolean(val) -> {:update_seq, val}

      # Numeric options
      {:limit, val} when is_integer(val) -> {:limit, val}
      {:skip, val} when is_integer(val) -> {:skip, val}
      {:group_level, val} when is_integer(val) -> {:group_level, val}

      # String/atom options
      {:stale, :ok} -> {:stale, "ok"}
      {:stale, :update_after} -> {:stale, "update_after"}
      {:stale, val} when is_binary(val) -> {:stale, val}

      # Key options - JSON encode complex values
      {:key, val} -> {:key, encode_key(val)}
      {:startkey, val} -> {:startkey, encode_key(val)}
      {:endkey, val} -> {:endkey, encode_key(val)}
      {:keys, val} when is_list(val) -> {:keys, Jason.encode!(val)}

      # Document ID options (always strings)
      {:startkey_docid, val} when is_binary(val) -> {:startkey_docid, val}
      {:endkey_docid, val} when is_binary(val) -> {:endkey_docid, val}

      # Pass through other options
      other -> other
    end)
  end

  @doc false
  defp encode_key(val) when is_binary(val), do: Jason.encode!(val)
  defp encode_key(val) when is_number(val), do: Jason.encode!(val)
  defp encode_key(val) when is_list(val), do: Jason.encode!(val)
  defp encode_key(val) when is_map(val), do: Jason.encode!(val)
  defp encode_key(val) when is_atom(val), do: Jason.encode!(Atom.to_string(val))
  defp encode_key(val), do: Jason.encode!(val)

  defp parse_row(row = %{"_id" => _id}) do
    Sofa.Doc.from_map(row)
  end

  defp parse_row(row) do
    row
  end

  defp parse_doc_row(%{"key" => _key, "doc" => doc}) do
    Sofa.Doc.from_map(doc)
  end

  defp parse_doc_row(doc = %{"id" => _id}) do
    Sofa.Doc.from_map(doc)
  end
end
