defmodule Sofa.Bulk do
  @moduledoc """
  Bulk operations for CouchDB.

  This module provides efficient bulk operations for creating, updating,
  and deleting multiple documents in a single request.

  ## Examples

      # Bulk insert documents
      docs = [
        %{_id: "doc1", type: "user", name: "Alice"},
        %{_id: "doc2", type: "user", name: "Bob"}
      ]
      {:ok, results} = Sofa.Bulk.docs(sofa, docs)

      # Bulk update with new_edits: false for replication
      {:ok, results} = Sofa.Bulk.docs(sofa, docs, new_edits: false)

      # Bulk delete documents
      docs_to_delete = [
        %{_id: "doc1", _rev: "1-abc", _deleted: true},
        %{_id: "doc2", _rev: "2-def", _deleted: true}
      ]
      {:ok, results} = Sofa.Bulk.docs(sofa, docs_to_delete)

      # Bulk get specific documents
      {:ok, results} = Sofa.Bulk.get(sofa, ["doc1", "doc2", "doc3"])
  """

  require Logger

  @doc """
  Insert, update, or delete multiple documents in a single request.

  ## Options

  - `:new_edits` - If false, prevents the database from assigning new revision IDs.
    Used primarily for replication. Default: true.
  - `:all_or_nothing` - (Deprecated in CouchDB 2.0+) Commit all or nothing. Default: false.

  ## Returns

  - `{:ok, results}` - List of results with :ok or :error for each document
  - `{:error, reason}` - If the bulk operation fails

  ## Examples

      docs = [
        %{_id: "doc1", name: "Alice"},
        %{_id: "doc2", name: "Bob"}
      ]

      {:ok, results} = Sofa.Bulk.docs(sofa, docs)
      # Returns: {:ok, [
      #   %{ok: true, id: "doc1", rev: "1-xxx"},
      #   %{ok: true, id: "doc2", rev: "1-yyy"}
      # ]}

      # With errors:
      # {:ok, [
      #   %{ok: true, id: "doc1", rev: "1-xxx"},
      #   %{error: "conflict", id: "doc2", rev: "1-yyy"}
      # ]}
  """
  @spec docs(Sofa.t(), list(map()), Keyword.t()) :: {:ok, list(map())} | {:error, any()}
  def docs(sofa = %Sofa{database: db}, documents, opts \\ []) when is_list(documents) do
    path = "#{db}/_bulk_docs"

    body = %{
      docs: documents
    }
    |> maybe_add_new_edits(opts)
    |> maybe_add_all_or_nothing(opts)

    case Sofa.raw(sofa, path, :post, body: Jason.encode!(body)) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, parse_bulk_results(resp.body)}
    end
  end

  @doc """
  Fetch multiple documents by their IDs in a single request.

  This is more efficient than making multiple individual GET requests.

  ## Options

  - `:include_docs` - Include full document bodies (default: true)
  - `:attachments` - Include attachment data (default: false)

  ## Examples

      {:ok, results} = Sofa.Bulk.get(sofa, ["doc1", "doc2", "doc3"])

      # With attachments
      {:ok, results} = Sofa.Bulk.get(sofa, ["doc1"], attachments: true)
  """
  @spec get(Sofa.t(), list(String.t()), Keyword.t()) :: {:ok, list(map())} | {:error, any()}
  def get(sofa = %Sofa{database: db}, doc_ids, opts \\ []) when is_list(doc_ids) do
    path = "#{db}/_bulk_get"

    include_docs = Keyword.get(opts, :include_docs, true)
    attachments = Keyword.get(opts, :attachments, false)

    body = %{
      docs: Enum.map(doc_ids, fn id -> %{id: id} end)
    }

    query_params = []
    |> maybe_add_param(:attachments, attachments)

    case Sofa.raw(sofa, path, :post, body: Jason.encode!(body), params: query_params) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, parse_bulk_get_results(resp.body, include_docs)}
    end
  end

  @doc """
  Fetch specific revisions of multiple documents.

  ## Examples

      docs = [
        %{id: "doc1", rev: "1-abc"},
        %{id: "doc2", rev: "2-def"}
      ]
      {:ok, results} = Sofa.Bulk.get_revs(sofa, docs)
  """
  @spec get_revs(Sofa.t(), list(map()), Keyword.t()) :: {:ok, list(map())} | {:error, any()}
  def get_revs(sofa = %Sofa{database: db}, doc_specs, opts \\ []) when is_list(doc_specs) do
    path = "#{db}/_bulk_get"

    include_docs = Keyword.get(opts, :include_docs, true)

    body = %{
      docs: Enum.map(doc_specs, fn spec ->
        case spec do
          %{id: id, rev: rev} -> %{id: id, rev: rev}
          %{"id" => id, "rev" => rev} -> %{id: id, rev: rev}
          _ -> spec
        end
      end)
    }

    case Sofa.raw(sofa, path, :post, body: Jason.encode!(body)) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, parse_bulk_get_results(resp.body, include_docs)}
    end
  end

  # Private helper functions

  defp maybe_add_new_edits(body, opts) do
    case Keyword.get(opts, :new_edits) do
      nil -> body
      val when is_boolean(val) -> Map.put(body, :new_edits, val)
      _ -> body
    end
  end

  defp maybe_add_all_or_nothing(body, opts) do
    case Keyword.get(opts, :all_or_nothing) do
      nil -> body
      val when is_boolean(val) -> Map.put(body, :all_or_nothing, val)
      _ -> body
    end
  end

  defp maybe_add_param(params, _key, false), do: params
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, true), do: [{key, true} | params]
  defp maybe_add_param(params, key, val), do: [{key, val} | params]

  @doc false
  def parse_bulk_results(results) when is_list(results) do
    Enum.map(results, fn result ->
      case result do
        %{"ok" => true, "id" => id, "rev" => rev} ->
          %{ok: true, id: id, rev: rev}

        %{"error" => error, "id" => id} ->
          %{error: error, id: id, reason: Map.get(result, "reason")}

        %{"error" => error, "id" => id, "rev" => rev} ->
          %{error: error, id: id, rev: rev, reason: Map.get(result, "reason")}

        other ->
          other
      end
    end)
  end

  @doc false
  def parse_bulk_results(body), do: body

  defp parse_bulk_get_results(%{"results" => results}, include_docs) do
    Enum.map(results, fn result ->
      id = result["id"]

      case result["docs"] do
        [%{"ok" => doc}] when include_docs ->
          %{id: id, ok: true, doc: Sofa.Doc.from_map(doc)}

        [%{"ok" => doc}] ->
          %{id: id, ok: true, rev: doc["_rev"]}

        [%{"error" => error}] ->
          %{id: id, error: error["error"], reason: error["reason"]}

        docs when is_list(docs) ->
          %{id: id, docs: docs}

        _ ->
          %{id: id, error: "not_found"}
      end
    end)
  end

  defp parse_bulk_get_results(body, _include_docs), do: body
end
