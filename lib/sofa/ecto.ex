defmodule Sofa.Ecto do
  @moduledoc """
  Ecto-style adapter for CouchDB.

  This module provides an Ecto-like interface for working with CouchDB,
  including schema definitions, changesets, and query composition.

  **Note:** This is not a full Ecto adapter (which would require implementing
  the `Ecto.Adapter` behaviour), but provides similar patterns and ergonomics.

  ## Features

  - Schema definitions with types
  - Changeset-based validation
  - Query composition
  - Automatic timestamps
  - Associations (embedded)
  - Custom validators

  ## Usage

      defmodule MyApp.User do
        use Sofa.Ecto.Schema

        schema "users" do
          field :name, :string
          field :email, :string
          field :age, :integer
          field :active, :boolean, default: true

          timestamps()
        end

        def changeset(user, params) do
          user
          |> cast(params, [:name, :email, :age, :active])
          |> validate_required([:name, :email])
          |> validate_format(:email, ~r/@/)
          |> validate_number(:age, greater_than: 0)
        end
      end

      # Create
      changeset = MyApp.User.changeset(%MyApp.User{}, %{name: "Alice", email: "alice@example.com"})
      {:ok, user} = Sofa.Ecto.insert(conn, changeset)

      # Read
      {:ok, user} = Sofa.Ecto.get(conn, MyApp.User, "user-id")

      # Update
      changeset = MyApp.User.changeset(user, %{name: "Alice Smith"})
      {:ok, updated} = Sofa.Ecto.update(conn, changeset)

      # Delete
      :ok = Sofa.Ecto.delete(conn, user)

  ## Queries

      import Sofa.Ecto.Query

      # Find users over 18
      query = from u in MyApp.User, where: u.age > 18, limit: 10
      {:ok, users} = Sofa.Ecto.all(conn, query)

      # Count active users
      query = from u in MyApp.User, where: u.active == true
      {:ok, count} = Sofa.Ecto.count(conn, query)
  """

  alias Sofa.Ecto.{Changeset, Query}

  @type conn :: Sofa.t()
  @type schema :: struct()
  @type changeset :: Changeset.t()
  @type query :: Query.t()
  @type id :: String.t()
  @type error :: {:error, term()}

  @doc """
  Inserts a new record using a changeset.

  ## Examples

      changeset = MyApp.User.changeset(%MyApp.User{}, params)
      {:ok, user} = Sofa.Ecto.insert(conn, changeset)
  """
  @spec insert(conn(), changeset()) :: {:ok, schema()} | error()
  def insert(conn, %Changeset{} = changeset) do
    case Changeset.apply_action(changeset, :insert) do
      {:ok, struct} ->
        Sofa.Document.save(conn, struct)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a record using a changeset.

  ## Examples

      changeset = MyApp.User.changeset(user, %{name: "New Name"})
      {:ok, updated} = Sofa.Ecto.update(conn, changeset)
  """
  @spec update(conn(), changeset()) :: {:ok, schema()} | error()
  def update(conn, %Changeset{} = changeset) do
    case Changeset.apply_action(changeset, :update) do
      {:ok, struct} ->
        Sofa.Document.save(conn, struct)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a record.

  ## Examples

      :ok = Sofa.Ecto.delete(conn, user)
  """
  @spec delete(conn(), schema()) :: :ok | error()
  def delete(conn, struct) do
    Sofa.Document.delete(conn, struct)
  end

  @doc """
  Gets a single record by ID.

  Returns `nil` if not found, raises if multiple records match.

  ## Examples

      user = Sofa.Ecto.get(conn, MyApp.User, "user-123")
  """
  @spec get(conn(), module(), id()) :: schema() | nil
  def get(conn, module, id) do
    case Sofa.Document.get(conn, module, id) do
      {:ok, struct} -> struct
      {:error, %Sofa.Error.NotFound{}} -> nil
      {:error, reason} -> raise "Failed to get document: #{inspect(reason)}"
    end
  end

  @doc """
  Gets a single record by ID, raises if not found.

  ## Examples

      user = Sofa.Ecto.get!(conn, MyApp.User, "user-123")
  """
  @spec get!(conn(), module(), id()) :: schema()
  def get!(conn, module, id) do
    case get(conn, module, id) do
      nil -> raise "Document not found: #{id}"
      struct -> struct
    end
  end

  @doc """
  Fetches all records from a query.

  ## Examples

      query = from u in MyApp.User, where: u.active == true
      {:ok, users} = Sofa.Ecto.all(conn, query)
  """
  @spec all(conn(), query() | module()) :: {:ok, [schema()]} | error()
  def all(conn, %Query{} = query) do
    {module, mango_query} = Query.to_mango(query)
    Sofa.Document.find(conn, module, mango_query)
  end

  def all(conn, module) when is_atom(module) do
    Sofa.Document.all(conn, module)
  end

  @doc """
  Fetches a single record from a query.

  Returns `nil` if not found, raises if multiple records match.

  ## Examples

      query = from u in MyApp.User, where: u.email == "alice@example.com"
      user = Sofa.Ecto.one(conn, query)
  """
  @spec one(conn(), query()) :: schema() | nil
  def one(conn, %Query{} = query) do
    query = Query.limit(query, 2)

    case all(conn, query) do
      {:ok, []} -> nil
      {:ok, [single]} -> single
      {:ok, [_ | _]} -> raise "Expected at most one result, got multiple"
      {:error, reason} -> raise "Query failed: #{inspect(reason)}"
    end
  end

  @doc """
  Fetches a single record from a query, raises if not found or multiple match.

  ## Examples

      query = from u in MyApp.User, where: u.email == "alice@example.com"
      user = Sofa.Ecto.one!(conn, query)
  """
  @spec one!(conn(), query()) :: schema()
  def one!(conn, query) do
    case one(conn, query) do
      nil -> raise "No record found"
      struct -> struct
    end
  end

  @doc """
  Counts records matching a query.

  ## Examples

      query = from u in MyApp.User, where: u.active == true
      {:ok, count} = Sofa.Ecto.count(conn, query)
  """
  @spec count(conn(), query() | module()) :: {:ok, non_neg_integer()} | error()
  def count(conn, %Query{} = query) do
    {module, mango_query} = Query.to_mango(query)
    Sofa.Document.count(conn, module, mango_query)
  end

  def count(conn, module) when is_atom(module) do
    Sofa.Document.count(conn, module)
  end
end
