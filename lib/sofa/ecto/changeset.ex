defmodule Sofa.Ecto.Changeset do
  @moduledoc """
  Changeset for validating and transforming data before persisting to CouchDB.

  Provides a subset of Ecto.Changeset functionality adapted for CouchDB.

  ## Example

      def changeset(user, params) do
        user
        |> cast(params, [:name, :email, :age])
        |> validate_required([:name, :email])
        |> validate_format(:email, ~r/@/)
        |> validate_number(:age, greater_than: 0, less_than: 150)
      end
  """

  defstruct [
    :data,
    :changes,
    :errors,
    :valid?,
    :action
  ]

  @type t :: %__MODULE__{
          data: struct(),
          changes: map(),
          errors: keyword(),
          valid?: boolean(),
          action: atom() | nil
        }

  @type error :: {String.t(), keyword()}

  @doc """
  Creates a changeset with the given changes.

  ## Example

      changeset = Changeset.change(%User{}, %{name: "Alice"})
  """
  @spec change(struct(), map()) :: t()
  def change(data, changes \\ %{}) do
    %__MODULE__{
      data: data,
      changes: changes,
      errors: [],
      valid?: true,
      action: nil
    }
  end

  @doc """
  Casts parameters into the changeset, filtering by allowed fields.

  ## Example

      changeset = cast(user, params, [:name, :email, :age])
  """
  @spec cast(struct() | t(), map(), [atom()]) :: t()
  def cast(data, params, allowed) when is_struct(data) do
    cast(change(data), params, allowed)
  end

  def cast(%__MODULE__{} = changeset, params, allowed) do
    changes =
      params
      |> Enum.filter(fn {key, _} -> key_allowed?(key, allowed) end)
      |> Enum.map(fn {key, value} -> {to_atom_key(key), value} end)
      |> Enum.into(%{})

    %{changeset | changes: Map.merge(changeset.changes, changes)}
  end

  defp key_allowed?(key, allowed) do
    atom_key = to_atom_key(key)
    atom_key in allowed
  rescue
    ArgumentError -> false
  end

  defp to_atom_key(key) when is_binary(key), do: String.to_existing_atom(key)
  defp to_atom_key(key) when is_atom(key), do: key

  @doc """
  Validates that required fields are present in the changeset.

  ## Example

      changeset = validate_required(changeset, [:name, :email])
  """
  @spec validate_required(t(), [atom()]) :: t()
  def validate_required(%__MODULE__{} = changeset, fields) do
    errors =
      Enum.reduce(fields, [], fn field, acc ->
        value = get_field(changeset, field)

        if is_nil(value) or value == "" do
          [{field, {"can't be blank", [validation: :required]}} | acc]
        else
          acc
        end
      end)

    add_errors(changeset, errors)
  end

  @doc """
  Validates a field matches a format (regex).

  ## Example

      changeset = validate_format(changeset, :email, ~r/@/)
  """
  @spec validate_format(t(), atom(), Regex.t()) :: t()
  def validate_format(%__MODULE__{} = changeset, field, regex) do
    value = get_field(changeset, field)

    if value && !Regex.match?(regex, to_string(value)) do
      add_error(changeset, field, "has invalid format", validation: :format)
    else
      changeset
    end
  end

  @doc """
  Validates a number field.

  ## Options

  - `:greater_than`
  - `:less_than`
  - `:greater_than_or_equal_to`
  - `:less_than_or_equal_to`
  - `:equal_to`

  ## Example

      changeset = validate_number(changeset, :age, greater_than: 0, less_than: 150)
  """
  @spec validate_number(t(), atom(), keyword()) :: t()
  def validate_number(%__MODULE__{} = changeset, field, opts) do
    value = get_field(changeset, field)

    if value do
      Enum.reduce(opts, changeset, fn {check, expected}, acc ->
        case check do
          :greater_than ->
            if value > expected,
              do: acc,
              else: add_error(acc, field, "must be greater than #{expected}", validation: check)

          :less_than ->
            if value < expected,
              do: acc,
              else: add_error(acc, field, "must be less than #{expected}", validation: check)

          :greater_than_or_equal_to ->
            if value >= expected,
              do: acc,
              else:
                add_error(acc, field, "must be greater than or equal to #{expected}",
                  validation: check
                )

          :less_than_or_equal_to ->
            if value <= expected,
              do: acc,
              else:
                add_error(acc, field, "must be less than or equal to #{expected}",
                  validation: check
                )

          :equal_to ->
            if value == expected,
              do: acc,
              else: add_error(acc, field, "must be equal to #{expected}", validation: check)

          _ ->
            acc
        end
      end)
    else
      changeset
    end
  end

  @doc """
  Validates a field is within a list of values.

  ## Example

      changeset = validate_inclusion(changeset, :status, ["active", "inactive", "pending"])
  """
  @spec validate_inclusion(t(), atom(), [any()]) :: t()
  def validate_inclusion(%__MODULE__{} = changeset, field, enum) do
    value = get_field(changeset, field)

    if value && value not in enum do
      add_error(changeset, field, "is invalid", validation: :inclusion)
    else
      changeset
    end
  end

  @doc """
  Validates a field is not in a list of values.

  ## Example

      changeset = validate_exclusion(changeset, :username, ["admin", "root", "system"])
  """
  @spec validate_exclusion(t(), atom(), [any()]) :: t()
  def validate_exclusion(%__MODULE__{} = changeset, field, enum) do
    value = get_field(changeset, field)

    if value && value in enum do
      add_error(changeset, field, "is reserved", validation: :exclusion)
    else
      changeset
    end
  end

  @doc """
  Validates the length of a string field.

  ## Options

  - `:min`
  - `:max`
  - `:is` - exact length

  ## Example

      changeset = validate_length(changeset, :name, min: 2, max: 100)
  """
  @spec validate_length(t(), atom(), keyword()) :: t()
  def validate_length(%__MODULE__{} = changeset, field, opts) do
    value = get_field(changeset, field)

    if value do
      length = String.length(to_string(value))

      Enum.reduce(opts, changeset, fn {check, expected}, acc ->
        case check do
          :min ->
            if length >= expected,
              do: acc,
              else: add_error(acc, field, "should be at least #{expected} character(s)", validation: :length, kind: :min, count: expected)

          :max ->
            if length <= expected,
              do: acc,
              else: add_error(acc, field, "should be at most #{expected} character(s)", validation: :length, kind: :max, count: expected)

          :is ->
            if length == expected,
              do: acc,
              else: add_error(acc, field, "should be #{expected} character(s)", validation: :length, kind: :is, count: expected)

          _ ->
            acc
        end
      end)
    else
      changeset
    end
  end

  @doc """
  Gets a field value from the changeset (preferring changes over data).

  ## Example

      email = get_field(changeset, :email)
  """
  @spec get_field(t(), atom()) :: any()
  def get_field(%__MODULE__{changes: changes, data: data}, key) do
    Map.get(changes, key, Map.get(data, key))
  end

  @doc """
  Gets a changed field value from the changeset.

  ## Example

      new_email = get_change(changeset, :email)
  """
  @spec get_change(t(), atom()) :: any()
  def get_change(%__MODULE__{changes: changes}, key) do
    Map.get(changes, key)
  end

  @doc """
  Applies the changeset changes to the data struct.

  Returns `{:ok, struct}` if valid, `{:error, changeset}` otherwise.

  ## Example

      case apply_action(changeset, :insert) do
        {:ok, user} -> # success
        {:error, changeset} -> # validation errors
      end
  """
  @spec apply_action(t(), atom()) :: {:ok, struct()} | {:error, t()}
  def apply_action(%__MODULE__{valid?: false} = changeset, action) do
    {:error, %{changeset | action: action}}
  end

  def apply_action(%__MODULE__{valid?: true, data: data, changes: changes}, _action) do
    struct = struct(data, changes)
    {:ok, struct}
  end

  # Private Functions

  defp add_error(%__MODULE__{} = changeset, field, message, opts) do
    error = {field, {message, opts}}
    add_errors(changeset, [error])
  end

  defp add_errors(%__MODULE__{errors: errors} = changeset, new_errors) do
    %{changeset | errors: errors ++ new_errors, valid?: false}
  end
end
