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

  def get(sofa = %Sofa{database: db}, raw_path, opts \\ []) when is_binary(raw_path) do
    case String.split(raw_path, "/", parts: 2) do
      [ddoc, view] ->
        path = "#{db}/_design/#{ddoc}/_view/#{view}"

        case call(sofa, :get, path, opts) do
          {:ok, resp} ->
            {:ok, from_map(resp)}

          error ->
            error
        end

      [ddoc] ->
        path = "#{db}/_design/#{ddoc}"
        call(sofa, :get, path, opts)
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
end
