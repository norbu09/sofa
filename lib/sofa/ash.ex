defmodule Sofa.Ash do
  @moduledoc """
  Ash Framework integration for Sofa.

  This module provides utilities for integrating Sofa with the Ash Framework,
  allowing you to use CouchDB as a data layer for Ash resources.

  **Note:** This is not a full Ash DataLayer implementation (which would require
  implementing the `Ash.DataLayer` behaviour), but provides patterns and helpers
  for using Sofa with Ash.

  ## Features

  - Resource-based document management
  - Changeset integration
  - Query composition
  - Action helpers
  - Relationship support (embedded)

  ## Usage

      defmodule MyApp.User do
        use Ash.Resource,
          data_layer: Sofa.Ash.DataLayer

        attributes do
          uuid_primary_key :id
          attribute :name, :string, allow_nil?: false
          attribute :email, :string, allow_nil?: false
          attribute :age, :integer
          attribute :active, :boolean, default: true

          create_timestamp :inserted_at
          update_timestamp :updated_at
        end

        actions do
          defaults [:create, :read, :update, :destroy]
        end

        code_interface do
          define_for MyApp.Api
          define :create
          define :read
          define :by_email, args: [:email]
        end

        calculations do
          calculate :display_name, :string, expr(name <> " (" <> email <> ")")
        end
      end

      # Using the resource
      {:ok, user} = MyApp.User.create(%{name: "Alice", email: "alice@example.com"})
      {:ok, user} = MyApp.User.by_email("alice@example.com")
      {:ok, updated} = MyApp.User.update(user, %{name: "Alice Smith"})

  ## Document Mapping

  Ash resources map to CouchDB documents with the following conventions:

  - Resource name → Database name (configurable)
  - Primary key → `_id` field
  - Attributes → Document fields
  - Timestamps → `inserted_at`/`updated_at` fields
  - Relationships → Embedded documents or references

  ## Configuration

      config :my_app, MyApp.User,
        database: "users",
        partition_key: :org_id  # Optional: for partitioned databases
  """

  @doc """
  Helper for converting Ash changesets to Sofa.Ecto changesets.

  ## Example

      ash_changeset = Ash.Changeset.for_create(User, :create, params)
      sofa_changeset = Sofa.Ash.to_sofa_changeset(ash_changeset)
  """
  @spec to_sofa_changeset(any()) :: Sofa.Ecto.Changeset.t()
  def to_sofa_changeset(ash_changeset) do
    # Extract data and changes from Ash changeset
    data = Map.get(ash_changeset, :data, %{})
    changes = Map.get(ash_changeset, :attributes, %{})

    # Create Sofa.Ecto changeset
    Sofa.Ecto.Changeset.change(data, changes)
  end

  @doc """
  Converts an Ash filter to a Mango selector.

  ## Example

      filter = Ash.Filter.parse(User, %{age: [greater_than: 18]})
      selector = Sofa.Ash.filter_to_selector(filter)
      # Returns: %{"age" => %{"$gt" => 18}}
  """
  @spec filter_to_selector(any()) :: map()
  def filter_to_selector(filter) when is_map(filter) do
    # Simple implementation for basic filters
    # A full implementation would parse Ash.Filter structures
    Enum.reduce(filter, %{}, fn {field, value}, acc ->
      Map.put(acc, to_string(field), convert_filter_value(value))
    end)
  end

  def filter_to_selector(_filter), do: %{}

  defp convert_filter_value([{:greater_than, value}]), do: %{"$gt" => value}
  defp convert_filter_value([{:less_than, value}]), do: %{"$lt" => value}
  defp convert_filter_value([{:greater_than_or_equal_to, value}]), do: %{"$gte" => value}
  defp convert_filter_value([{:less_than_or_equal_to, value}]), do: %{"$lte" => value}
  defp convert_filter_value([{:equal, value}]), do: value
  defp convert_filter_value([{:not_equal, value}]), do: %{"$ne" => value}
  defp convert_filter_value([{:in, values}]), do: %{"$in" => values}
  defp convert_filter_value(value), do: value

  @doc """
  Gets the database name for an Ash resource.

  ## Example

      database = Sofa.Ash.database_for(MyApp.User)
      # Returns: "users"
  """
  @spec database_for(module()) :: String.t()
  def database_for(resource) when is_atom(resource) do
    # Try to get from config
    config = Application.get_env(:sofa, resource, [])

    case Keyword.fetch(config, :database) do
      {:ok, database} ->
        database

      :error ->
        # Default: use resource name (lowercased, pluralized)
        resource
        |> Module.split()
        |> List.last()
        |> String.downcase()
        |> pluralize()
    end
  end

  @doc """
  Gets the partition key for an Ash resource (if using partitioned databases).

  ## Example

      partition_key = Sofa.Ash.partition_key_for(MyApp.User)
      # Returns: :org_id or nil
  """
  @spec partition_key_for(module()) :: atom() | nil
  def partition_key_for(resource) when is_atom(resource) do
    config = Application.get_env(:sofa, resource, [])
    Keyword.get(config, :partition_key)
  end

  @doc """
  Helper for creating resources with Sofa.

  ## Example

      {:ok, user} = Sofa.Ash.create(conn, MyApp.User, params)
  """
  @spec create(Sofa.t(), module(), map()) :: {:ok, struct()} | {:error, term()}
  def create(conn, resource, params) do
    database = database_for(resource)

    # Create document
    case Sofa.Doc.create(conn, database, params) do
      {:ok, result} ->
        # Build resource struct
        struct_data = Map.merge(params, %{
          "_id" => result["id"],
          "_rev" => result["rev"]
        })

        {:ok, struct(resource, atomize_keys(struct_data))}

      error ->
        error
    end
  end

  @doc """
  Helper for reading resources with Sofa.

  ## Example

      {:ok, user} = Sofa.Ash.get(conn, MyApp.User, "user-123")
  """
  @spec get(Sofa.t(), module(), String.t()) :: {:ok, struct()} | {:error, term()}
  def get(conn, resource, id) do
    database = database_for(resource)
    path = "#{database}/#{id}"

    case Sofa.Doc.get(conn, path) do
      {:ok, doc} ->
        {:ok, struct(resource, atomize_keys(doc))}

      error ->
        error
    end
  end

  @doc """
  Helper for updating resources with Sofa.

  ## Example

      {:ok, updated} = Sofa.Ash.update(conn, resource, params)
  """
  @spec update(Sofa.t(), struct(), map()) :: {:ok, struct()} | {:error, term()}
  def update(conn, resource_struct, params) do
    database = database_for(resource_struct.__struct__)
    id = Map.get(resource_struct, :_id) || Map.get(resource_struct, :id)
    rev = Map.get(resource_struct, :_rev)

    doc =
      params
      |> Map.put("_id", id)
      |> Map.put("_rev", rev)

    case Sofa.Doc.create(conn, database, doc) do
      {:ok, result} ->
        struct_data = Map.merge(params, %{
          "_id" => result["id"],
          "_rev" => result["rev"]
        })

        {:ok, struct(resource_struct.__struct__, atomize_keys(struct_data))}

      error ->
        error
    end
  end

  @doc """
  Helper for deleting resources with Sofa.

  ## Example

      :ok = Sofa.Ash.delete(conn, user)
  """
  @spec delete(Sofa.t(), struct()) :: :ok | {:error, term()}
  def delete(conn, resource_struct) do
    database = database_for(resource_struct.__struct__)
    id = Map.get(resource_struct, :_id) || Map.get(resource_struct, :id)
    rev = Map.get(resource_struct, :_rev)

    case Sofa.Doc.delete(conn, database, id, rev) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Helper for querying resources with Sofa.

  ## Example

      selector = %{age: %{"$gt" => 18}, active: true}
      {:ok, users} = Sofa.Ash.query(conn, MyApp.User, selector)
  """
  @spec query(Sofa.t(), module(), map(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def query(conn, resource, selector, opts \\ []) do
    database = database_for(resource)

    case Sofa.Mango.query(conn, database, selector, opts) do
      {:ok, %{docs: docs}} ->
        structs = Enum.map(docs, fn doc -> struct(resource, atomize_keys(doc)) end)
        {:ok, structs}

      error ->
        error
    end
  end

  @doc """
  Helper for counting resources with Sofa.

  ## Example

      {:ok, count} = Sofa.Ash.count(conn, MyApp.User, %{active: true})
  """
  @spec count(Sofa.t(), module(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(conn, resource, selector \\ %{}) do
    database = database_for(resource)
    opts = [limit: 0, execution_stats: true]

    case Sofa.Mango.query(conn, database, selector, opts) do
      {:ok, %{execution_stats: %{total_docs_examined: count}}} ->
        {:ok, count}

      {:ok, _} ->
        # Fallback
        case query(conn, resource, selector) do
          {:ok, results} -> {:ok, length(results)}
          error -> error
        end

      error ->
        error
    end
  end

  # Private Functions

  defp atomize_keys(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> atomize_key(k, v) end)
    |> Enum.into(%{})
  end

  defp atomize_key(k, v) when is_binary(k) do
    {String.to_existing_atom(k), v}
  rescue
    ArgumentError -> {k, v}
  end

  defp atomize_key(k, v), do: {k, v}

  defp pluralize(word) do
    # Simple pluralization
    cond do
      String.ends_with?(word, "s") -> word
      String.ends_with?(word, "y") -> String.replace_suffix(word, "y", "ies")
      true -> word <> "s"
    end
  end
end
