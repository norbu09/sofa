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
          offset: body[:offset]
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
          offset: body[:offset]
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

  @spec get(Sofa.t(), String.t(), Keyword.t()) :: {:error, any()} | {:ok, Sofa.View.t()}
  def get(sofa = %Sofa{database: db}, raw_path, opts \\ []) when is_binary(raw_path) do
    case String.split(raw_path, "/", parts: 2) do
      [ddoc, view] ->
        path = "#{db}/_design/#{ddoc}/_view/#{view}"

        case call(sofa, :get, path, opts) do
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
        call(sofa, :get, path, opts)
    end
  end

  @spec all_docs(Sofa.t(), Keyword.t()) :: {:error, any()} | {:ok, Sofa.View.t()}
  def all_docs(sofa = %Sofa{database: db}, opts \\ []) do
    path = "#{db}/_all_docs"

    case call(sofa, :get, path, opts) do
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
