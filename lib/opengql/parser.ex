defmodule OpenGQL.Parser do
  @moduledoc """
  Parser entrypoint for the supported OpenGQL subset.

  The implementation uses the Erlang `:leex` + `:yecc` backend and preserves
  the historical return tuple shape:

      {:ok, [{:statement, clauses}], "", %{}, line, offset}
      {:error, reason, rest, %{}, line, offset}
  """

  @type parse_result ::
          {:ok, [{:statement, keyword()}], binary(), map(), pos_integer(), non_neg_integer()}
          | {:error, binary(), binary(), map(), pos_integer(), non_neg_integer()}

  @spec parse(binary()) :: parse_result
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)
    chars = String.to_charlist(trimmed)

    with {:ok, tokens, _end_line} <- :opengql_lexer.string(chars),
         {:ok, clauses} <- :opengql_parser.parse(tokens) do
      {:ok, [{:statement, clauses}], "", %{}, 1, String.length(trimmed)}
    else
      {:error, {line, _module, reason}, remaining} ->
        {:error, normalize_reason(reason), normalize_rest(remaining), %{}, line, 0}

      {:error, {line, _module, reason}} ->
        {:error, normalize_reason(reason), "", %{}, line, 0}

      {:error, {line, _module, reason, _token}} ->
        {:error, normalize_reason(reason), "", %{}, line, 0}

      other ->
        {:error, inspect(other), "", %{}, 1, 0}
    end
  end

  # Keep illegal-token formatting stable across Elixir versions, which differ
  # in how charlists are rendered by inspect/1.
  defp normalize_reason({:illegal, chars}) when is_list(chars) do
    "{:illegal, ~c" <> inspect(List.to_string(chars)) <> "}"
  end

  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason) when is_list(reason), do: IO.iodata_to_binary(reason)
  defp normalize_reason(reason), do: inspect(reason)

  defp normalize_rest(rest) when is_binary(rest), do: rest
  defp normalize_rest(rest) when is_list(rest), do: IO.iodata_to_binary(rest)
  defp normalize_rest(_rest), do: ""
end
