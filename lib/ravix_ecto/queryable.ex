defmodule Ravix.Ecto.Queryable do
  @behaviour Ecto.Adapter.Queryable

  require OK

  alias Ravix.Ecto.Parser.QueryParser.QueryInfo
  alias Ravix.Ecto.Parser.QueryParser
  alias Ravix.Ecto.Executor

  @impl Ecto.Adapter.Queryable
  def prepare(function, query) do
    {:nocache, {function, query}}
  end

  @impl Ecto.Adapter.Queryable
  def execute(adapter_meta, _query_meta, {:nocache, {function, query}}, params, _opts) do
    document_type = get_struct_from_query(query)

    case apply(QueryParser, function, [query, params]) do
      %QueryInfo{kind: :read} = query ->
        case Executor.query(query.raven_query, adapter_meta) do
          {:error, err} ->
            {:error, err}

          {count, rows} ->
            {count, Enum.map(rows, fn row -> process_document(row, query, document_type) end)}
        end

      %QueryInfo{kind: :delete} = query ->
        case Executor.query(query.raven_query, adapter_meta, :delete) do
          {:error, err} -> {:error, err}
          _ -> {-1, nil}
        end

      %QueryInfo{kind: :update} = query ->
        case Executor.query(query.raven_query, adapter_meta, :update) do
          {:error, err} -> {:error, err}
          _ -> {-1, nil}
        end
    end
  end

  @impl Ecto.Adapter.Queryable
  def stream(_adapter_meta, _query_meta, {:nocache, {_function, _query}}, _params, _opts) do
    raise "Stream is not yet supported by the Ravix Ecto Driver"
  end

  defp get_struct_from_query(%Ecto.Query{from: %Ecto.Query.FromExpr{source: {_coll, nil}}}),
    do: nil

  defp get_struct_from_query(%Ecto.Query{from: %Ecto.Query.FromExpr{source: {_coll, struct}}}),
    do: struct.__struct__()

  defp get_struct_from_query(_), do: nil

  defp process_document(document, %{fields: fields, pk: pk}, struct) do
    Enum.map(fields, fn
      {:field, ^pk, _field} ->
        Map.get(document, "id()")

      {:field, name, _field} ->
        if Map.has_key?(document, Atom.to_string(name)) == false && struct != nil do
          Map.get(struct, name)
        else
          Map.get(document, Atom.to_string(name))
        end |> remap_nil_list()

      _field ->
        document
    end)
  end

  # Jason is encoding null as a list[nil], need to check
  defp remap_nil_list([nil]), do: nil
  defp remap_nil_list(value), do: value
end
