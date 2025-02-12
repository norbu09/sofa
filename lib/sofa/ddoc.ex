defmodule Sofa.DDoc do
  require Logger

  @moduledoc """
  Documentation for `Sofa.DDoc`, a test-driven idiomatic Apache CouchDB client.

  > If the only tool you have is CouchDB, then
  > everything looks like {:ok, :relax}

  ## Examples

  iex> Sofa.Doc.new()

  """

  defstruct views: %{},
            language: "javascript",
            id: "",
            rev: ""

  @type t :: %__MODULE__{
          views: %{},
          id: binary,
          rev: nil | binary,
          language: binary
        }

  @doc """
  Creates a new (empty) document
  """

  def get(sofa = %Sofa{database: db}, ddoc) when is_binary(ddoc) do
    case Sofa.raw(sofa, db <> "/_design/" <> ddoc, :get) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp)}
    end
  end

  def info(sofa = %Sofa{database: db}, ddoc) when is_binary(ddoc) do
    case Sofa.raw(sofa, db <> "/_design/" <> ddoc, :head) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, resp}
    end
  end

  @spec create(Sofa.t(), String.t(), map()) :: {:error, any()} | {:ok, Sofa.t(), any()}
  def create(sofa = %Sofa{database: db}, name, doc) when is_map(doc) do
    Logger.debug("Creating design document with name #{name}")

    ddoc =
      to_map(doc)
      |> Map.delete("_rev")

    case Sofa.raw(sofa, db <> "/_design/" <> name, :put, [rev: doc.rev], ddoc) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, Sofa.Doc.from_map(resp.body)}
    end
  end

  def create(sofa = %Sofa{database: db}, doc) when is_map(doc) do
    case Sofa.raw(sofa, db, :put, [], to_map(doc)) do
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
  def update(sofa = %Sofa{database: nil}, db, rev, doc = %Sofa.Doc{body: body}) do
    case Sofa.raw(sofa, db <> "/" <> doc.id, :put, [{"rev", rev}], Map.put(body, "_id", doc.id)) do
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
  def update(sofa = %Sofa{database: db}, doc = %Sofa.Doc{body: body}) do
    case Sofa.raw(
           sofa,
           db <> "/" <> doc.id,
           :put,
           [{"rev", doc.rev}],
           Map.put(body, "_id", doc.id)
         ) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, from_map(resp.body)}
    end
  end

  def list(sofa = %Sofa{database: db}, opts \\ []) do
    case Sofa.raw(sofa, db <> "/_design_docs", :get, opts) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, Sofa.View.from_map(resp)}
    end
  end

  @spec from_map(map()) :: %Sofa.View{}
  def from_map(%Sofa.Response{body: body}) do
    Logger.debug("Response: #{inspect(body)}")

    rows = Enum.map(body["views"], fn {k, v} -> %{k => parse_row(v)} end)

    %Sofa.DDoc{
      views: rows,
      id: body["_id"],
      rev: body["_rev"],
      language: body["language"]
    }
  end

  def to_map(doc = %Sofa.DDoc{id: raw_id}) do
    # id = String.trim_leading(raw_id, "_design/")

    rows =
      Enum.reduce(doc.views, %{}, fn x, acc ->
        [k] = Map.keys(x)
        Map.put(acc, k, parse_ddoc_row(x[k]))
      end)

    %{
      "views" => rows,
      "_id" => raw_id,
      "_rev" => doc.rev,
      "language" => doc.language
    }
  end

  defp parse_row(row = %{"reduce" => reduce}) do
    %{map: row["map"], reduce: reduce}
  end

  defp parse_row(row) do
    %{map: row["map"]}
  end

  defp parse_ddoc_row(row = %{reduce: reduce}) do
    %{"map" => row.map, "reduce" => reduce}
  end

  defp parse_ddoc_row(row) do
    %{"map" => row.map}
  end
end
