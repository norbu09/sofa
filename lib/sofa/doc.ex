defmodule Sofa.Doc do
  require Logger

  @moduledoc """
  Documentation for `Sofa.Doc`, a test-driven idiomatic Apache CouchDB client.

  > If the only tool you have is CouchDB, then
  > everything looks like {:ok, :relax}

  ## Examples

  iex> Sofa.Doc.new()

  """

  defstruct attachments: %{},
            body: %{},
            id: "",
            rev: "",
            # type is used to allow Sofa to fake reading and writing Elixir
            # Structs directly to/from CouchDB, by duck-typing an additional
            # `type` key, which contains the usual `__MODULE__` struct name.
            type: nil

  @type t :: %__MODULE__{
          attachments: %{},
          id: binary,
          rev: nil | binary,
          type: atom
        }

  @doc """
  Creates a new (empty) document
  """

  @spec new(String.t() | %{}) :: %Sofa.Doc{}
  def new(id) when is_binary(id) do
    %Sofa.Doc{id: id, body: %{}}
  end

  def new(%{id: id, body: body}) when is_binary(id) and is_map(body) do
    %Sofa.Doc{id: id, body: body}
  end

  def new(%{id: id}) when is_binary(id) do
    %Sofa.Doc{id: id, body: %{}}
  end

  @doc """
  Check if doc exists via `HEAD /:db/:doc and returns either:

  - {:error, _reason} # an unhandled error occurred
  - {:error, not_found} # doc doesn't exist
  - {:ok, %Sofa.Doc{}} # doc exists and has metadata
  """
  @spec exists(Sofa.t(), String.t()) :: {:error, any()} | {:ok, %{}}
  def exists(sofa = %Sofa{database: nil}, path) when is_binary(path) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, doc] ->
        exists(%Sofa{sofa | database: db}, doc)

      _ ->
        {:error, :db_not_found}
    end
  end

  def exists(sofa = %Sofa{database: db}, doc) when is_binary(doc) do
    case Sofa.raw(sofa, db <> "/" <> doc, :head) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa,
       %Sofa.Response{
         status: 200,
         headers: %{etag: etag}
       }} ->
        {:ok, %Sofa.Doc{id: doc, rev: etag}}

      {:ok, _sofa,
       %Sofa.Response{
         status: 404
       }} ->
        {:error, :not_found}
    end
  end

  @doc """
  Check if doc exists via `HEAD /:db/:doc and returns either true or false
  """
  @spec exists?(Sofa.t(), String.t()) :: false | true
  def exists?(sofa = %Sofa{database: nil}, path) when is_binary(path) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, doc] ->
        exists?(%Sofa{sofa | database: db}, doc)

      _ ->
        {:error, :db_not_found}
    end
  end

  def exists?(sofa = %Sofa{database: db}, doc) when is_binary(doc) do
    case Sofa.raw(sofa, db <> "/" <> doc, :head) do
      {:ok, _sofa,
       %Sofa.Response{
         status: 200,
         headers: %{etag: _etag}
       }} ->
        true

      _ ->
        false
    end
  end

  @doc """
  Converts internal %Sofa.Doc{} format to CouchDB-native JSON-friendly map
  """
  @spec to_map(%Sofa.Doc{}) :: map()
  def to_map(doc = %Sofa.Doc{}) do
    new_doc =
      doc.body
      |> Map.put("_id", doc.id)
      |> Map.put("_rev", doc.rev)
      |> Map.put("type", doc.type)

    if doc.attachments, do: Map.put(new_doc, "attachments", doc.attachments), else: new_doc
  end

  @doc """
  Converts CouchDB-native JSON-friendly map to internal %Sofa.Doc{} format
  """
  @spec from_map(map()) :: %Sofa.Doc{}
  def from_map(m = %{"id" => id}) do
    # remove all keys that are defined already in the struct
    body =
      Map.drop(
        m,
        Map.from_struct(%Sofa.Doc{}) |> Map.keys() |> Enum.map(fn x -> Atom.to_string(x) end)
      )

    # grab the rest we need them
    rev = Map.get(m, "rev", nil)
    atts = Map.get(m, "attachments", nil)
    type = Map.get(m, "type", nil)
    %Sofa.Doc{attachments: atts, body: body, id: id, rev: rev, type: type}
  end

  def from_map(m = %{"_id" => id}) do
    # remove all keys that are defined already in the struct
    drops =
      Map.from_struct(%Sofa.Doc{}) |> Map.keys() |> Enum.map(fn x -> Atom.to_string(x) end)

    body =
      Map.drop(
        m,
        drops ++ ["_id", "_rev"]
      )

    # grab the rest we need them
    rev = Map.get(m, "_rev", nil)
    atts = Map.get(m, "attachments", nil)
    type = Map.get(m, "type", nil)
    %Sofa.Doc{attachments: atts, body: body, id: id, rev: rev, type: type}
  end

  # this would be a Protocol for people to defimpl on their own structs
  # @spec from_struct(map()) :: %Sofa.Doc{}
  # def from_struct(m = %{id: id, __Struct__: type}) do
  # end

  # @doc """
  # create an empty doc
  # """

  #   @spec new() :: {%Sofa.Doc.t()}
  #   def new(), do: new(Sofa.Doc)

  @doc """
  create doc
  """
  @spec create(Sofa.t(), String.t(), map()) :: {:error, any()} | {:ok, Sofa.t(), any()}
  def create(sofa = %Sofa{database: nil}, path, doc) when is_map(doc) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, id] ->
        Logger.debug("Got DB: #{db} and ID: #{id}")
        create(%Sofa{sofa | database: db}, id, doc)

      [db] ->
        Logger.debug("Got DB: #{db}")
        create(%Sofa{sofa | database: db}, doc)

      _ ->
        {:error, :db_not_found}
    end
  end

  def create(sofa = %Sofa{database: db}, id, doc) when is_map(doc) do
    Logger.debug("Creating document with ID #{id}")

    case Sofa.raw(sofa, db <> "/" <> id, :put, [], doc) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  def create(sofa = %Sofa{database: db}, doc) when is_map(doc) do
    case Sofa.raw(sofa, db, :post, [], doc) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  @doc """
  update doc
  """
  @spec update(Sofa.t(), String.t(), String.t(), Sofa.Doc.t()) ::
          {:error, any()} | {:ok, Sofa.Doc.t()}
  def update(sofa = %Sofa{database: nil}, db, rev, doc = %Sofa.Doc{body: _body}) do
    case Sofa.raw(sofa, db <> "/" <> doc.id, :put, [{"rev", rev}], to_map(doc)) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  @spec update(Sofa.t(), String.t(), Sofa.Doc.t()) :: {:error, any()} | {:ok, Sofa.Doc.t()}
  def update(sofa = %Sofa{database: nil}, db, doc = %Sofa.Doc{}) do
    update(sofa, db, doc.rev, doc)
  end

  @spec update(Sofa.t(), String.t(), Sofa.Doc.t()) :: {:error, any()} | {:ok, Sofa.Doc.t()}
  def update(sofa = %Sofa{}, rev, doc = %Sofa.Doc{}) do
    update(sofa, %Sofa.Doc{doc | rev: rev})
  end

  @spec update(Sofa.t(), Sofa.Doc.t()) :: {:error, any()} | {:ok, Sofa.Doc.t()}
  def update(sofa = %Sofa{database: db}, doc = %Sofa.Doc{body: _body}) do
    case Sofa.raw(
           sofa,
           db <> "/" <> doc.id,
           :put,
           [{"rev", doc.rev}],
           to_map(doc)
         ) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  @spec get(Sofa.t(), String.t()) ::
          {:error, any()} | {:ok, Sofa.Doc.t()}
  def get(sofa = %Sofa{database: nil}, path) when is_binary(path) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, id] ->
        get(%Sofa{sofa | database: db}, id)

      _ ->
        {:error, :db_not_found}
    end
  end

  def get(sofa = %Sofa{database: db}, id) when is_binary(id) do
    case Sofa.raw(sofa, db <> "/" <> id, :get) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  @spec delete(Sofa.t(), String.t(), String.t()) :: {:error, any()} | {:ok, Sofa.Doc.t()}
  def delete(_sofa, nil, _rev) do
    {:error, :doc_id_invalid}
  end

  def delete(sofa = %Sofa{database: nil}, path, rev) when is_binary(path) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, id] ->
        delete(%Sofa{sofa | database: db}, id, rev)

      _ ->
        {:error, :db_not_found}
    end
  end

  def delete(sofa = %Sofa{database: db}, id, rev) when is_binary(id) do
    case Sofa.raw(sofa, db <> "/" <> id, :delete, [{"rev", rev}]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end
end
