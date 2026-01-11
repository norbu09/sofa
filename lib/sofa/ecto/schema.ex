defmodule Sofa.Ecto.Schema do
  @moduledoc """
  Schema definition macro for Ecto-style CouchDB documents.

  Provides a familiar Ecto schema syntax for defining CouchDB document structures.

  ## Example

      defmodule MyApp.User do
        use Sofa.Ecto.Schema

        schema "users" do
          field :name, :string
          field :email, :string
          field :age, :integer
          field :metadata, :map
          field :tags, {:array, :string}

          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Sofa.Ecto.Schema, only: [schema: 2, field: 2, field: 3, timestamps: 0, timestamps: 1]
      use Sofa.Document, db: nil

      Module.register_attribute(__MODULE__, :fields, accumulate: true)
      Module.register_attribute(__MODULE__, :database_name, [])
    end
  end

  @doc """
  Defines a schema with the given database name and fields.

  ## Example

      schema "users" do
        field :name, :string
        field :email, :string
      end
  """
  defmacro schema(database, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :database_name, unquote(database))

      # Always include _id and _rev
      Module.put_attribute(__MODULE__, :fields, {:_id, :string, nil})
      Module.put_attribute(__MODULE__, :fields, {:_rev, :string, nil})

      unquote(block)

      @doc false
      def database, do: @database_name

      @doc false
      def __schema__(:fields) do
        @fields |> Enum.reverse() |> Enum.map(fn {name, _, _} -> name end)
      end

      @doc false
      def __schema__(:types) do
        @fields
        |> Enum.reverse()
        |> Enum.map(fn {name, type, _} -> {name, type} end)
        |> Enum.into(%{})
      end

      @doc false
      def __schema__(:defaults) do
        @fields
        |> Enum.reverse()
        |> Enum.reject(fn {_, _, default} -> is_nil(default) end)
        |> Enum.map(fn {name, _, default} -> {name, default} end)
        |> Enum.into(%{})
      end

      defstruct __schema__(:fields)
    end
  end

  @doc """
  Defines a field in the schema.

  ## Options

  - `:default` - Default value for the field

  ## Supported Types

  - `:string`
  - `:integer`
  - `:float`
  - `:boolean`
  - `:map`
  - `:naive_datetime`
  - `:utc_datetime`
  - `{:array, inner_type}`
  - `{:embed, module}` - For embedded schemas
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      default = Keyword.get(unquote(opts), :default)
      Module.put_attribute(__MODULE__, :fields, {unquote(name), unquote(type), default})
    end
  end

  @doc """
  Adds `inserted_at` and `updated_at` timestamp fields.

  ## Options

  - `:type` - Type of timestamp (`:naive_datetime` or `:utc_datetime`, default: `:utc_datetime`)
  """
  defmacro timestamps(opts \\ []) do
    quote do
      type = Keyword.get(unquote(opts), :type, :utc_datetime)
      Module.put_attribute(__MODULE__, :fields, {:inserted_at, type, nil})
      Module.put_attribute(__MODULE__, :fields, {:updated_at, type, nil})
    end
  end
end
