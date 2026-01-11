defmodule Sofa.Ecto.Query do
  @moduledoc """
  Query composition for CouchDB using Ecto-style syntax.

  Translates Ecto-like queries into CouchDB Mango queries.

  ## Example

      import Sofa.Ecto.Query

      # Simple query
      query = from u in MyApp.User, where: u.age > 18

      # Complex query
      query =
        from u in MyApp.User,
        where: u.active == true and u.age > 18,
        order_by: [desc: u.inserted_at],
        limit: 10,
        offset: 20

      {:ok, users} = Sofa.Ecto.all(conn, query)
  """

  defstruct [
    :from,
    :where,
    :order_by,
    :limit,
    :offset,
    :select
  ]

  @type t :: %__MODULE__{
          from: module(),
          where: map() | nil,
          order_by: list() | nil,
          limit: integer() | nil,
          offset: integer() | nil,
          select: list() | nil
        }

  @doc """
  Creates a query.

  ## Examples

      query = from u in MyApp.User
      query = from u in MyApp.User, where: u.age > 18
  """
  defmacro from(expr, kw \\ []) do
    {binding, module} = extract_binding(expr)

    quote do
      query = %Sofa.Ecto.Query{from: unquote(module)}
      unquote(build_query(binding, kw))
    end
  end

  @doc """
  Adds a where clause to a query.

  ## Example

      query = query |> where([u], u.age > 18)
  """
  defmacro where(query, binding, expr) do
    quote do
      selector = unquote(translate_where(binding, expr))

      %{unquote(query) | where: merge_selectors(unquote(query).where, selector)}
    end
  end

  @doc """
  Sets the limit for a query.

  ## Example

      query = query |> limit(10)
  """
  def limit(%__MODULE__{} = query, count) do
    %{query | limit: count}
  end

  @doc """
  Sets the offset for a query.

  ## Example

      query = query |> offset(20)
  """
  def offset(%__MODULE__{} = query, count) do
    %{query | offset: count}
  end

  @doc """
  Sets the order_by for a query.

  ## Example

      query = query |> order_by([u], asc: u.name)
      query = query |> order_by([u], desc: u.inserted_at)
  """
  defmacro order_by(query, _binding, fields) do
    quote do
      unquote(query)
      |> Map.put(:order_by, unquote(translate_order_by(fields)))
    end
  end

  @doc """
  Converts a query to a Mango query map.

  Returns `{module, mango_query}`.
  """
  @spec to_mango(t()) :: {module(), map()}
  def to_mango(%__MODULE__{} = query) do
    mango =
      %{}
      |> add_selector(query.where)
      |> add_limit(query.limit)
      |> add_skip(query.offset)
      |> add_sort(query.order_by)
      |> add_fields(query.select)

    {query.from, mango}
  end

  # Private Functions

  defp extract_binding({:in, _, [binding, module]}) do
    {binding, module}
  end

  defp build_query(binding, kw) do
    Enum.reduce(kw, quote(do: query), fn {key, value}, acc ->
      case key do
        :where ->
          quote do
            where(unquote(acc), unquote([binding]), unquote(value))
          end

        :limit ->
          quote do
            limit(unquote(acc), unquote(value))
          end

        :offset ->
          quote do
            offset(unquote(acc), unquote(value))
          end

        :order_by ->
          quote do
            order_by(unquote(acc), unquote([binding]), unquote(value))
          end

        _ ->
          acc
      end
    end)
  end

  defp translate_where(_binding, expr) do
    translate_expr(expr)
  end

  defp translate_expr({:==, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => value}
  end

  defp translate_expr({:!=, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => %{"$ne" => value}}
  end

  defp translate_expr({:>, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => %{"$gt" => value}}
  end

  defp translate_expr({:<, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => %{"$lt" => value}}
  end

  defp translate_expr({:>=, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => %{"$gte" => value}}
  end

  defp translate_expr({:<=, _, [left, right]}) do
    field = extract_field(left)
    value = extract_value(right)
    %{to_string(field) => %{"$lte" => value}}
  end

  defp translate_expr({:and, _, [left, right]}) do
    %{"$and" => [translate_expr(left), translate_expr(right)]}
  end

  defp translate_expr({:or, _, [left, right]}) do
    %{"$or" => [translate_expr(left), translate_expr(right)]}
  end

  defp translate_expr({:in, _, [left, right]}) do
    field = extract_field(left)
    values = extract_value(right)
    %{to_string(field) => %{"$in" => values}}
  end

  defp translate_expr({:not, _, [expr]}) do
    %{"$not" => translate_expr(expr)}
  end

  defp translate_expr(other) do
    # Fallback for literal values or complex expressions
    quote do: unquote(other)
  end

  defp extract_field({{:., _, [{binding, _, _}, field]}, _, _}) when is_atom(binding) do
    field
  end

  defp extract_field({field, _, _}) when is_atom(field) do
    field
  end

  defp extract_value({:^, _, [value]}) do
    # Pinned variable
    quote do: unquote(value)
  end

  defp extract_value(value) when is_list(value) or is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value) do
    value
  end

  defp extract_value(value) do
    quote do: unquote(value)
  end

  defp translate_order_by(fields) when is_list(fields) do
    Enum.map(fields, fn
      {direction, {{:., _, [_, field]}, _, _}} ->
        direction_str = if direction == :asc, do: "asc", else: "desc"
        %{to_string(field) => direction_str}

      {direction, {field, _, _}} ->
        direction_str = if direction == :asc, do: "asc", else: "desc"
        %{to_string(field) => direction_str}
    end)
  end

  defp merge_selectors(nil, selector), do: selector
  defp merge_selectors(selector, nil), do: selector

  defp merge_selectors(s1, s2) do
    %{"$and" => [s1, s2]}
  end

  defp add_selector(mango, nil), do: mango
  defp add_selector(mango, selector), do: Map.put(mango, :selector, selector)

  defp add_limit(mango, nil), do: mango
  defp add_limit(mango, limit), do: Map.put(mango, :limit, limit)

  defp add_skip(mango, nil), do: mango
  defp add_skip(mango, skip), do: Map.put(mango, :skip, skip)

  defp add_sort(mango, nil), do: mango
  defp add_sort(mango, sort), do: Map.put(mango, :sort, sort)

  defp add_fields(mango, nil), do: mango
  defp add_fields(mango, fields), do: Map.put(mango, :fields, fields)
end
