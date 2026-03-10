defmodule OpenGQL.ParserWrapperTest do
  use ExUnit.Case, async: false

  alias OpenGQL.Parser

  test "normalizes lexer illegal-token errors" do
    assert {:error, "{:illegal, ~c\"@\"}", "", %{}, 1, 0} =
             Parser.parse("MATCH @ RETURN a")
  end

  test "normalizes yecc syntax errors" do
    assert {:error, "syntax error before: return", "", %{}, 1, 0} =
             Parser.parse("MATCH (a RETURN a")
  end

  test "normalizes binary reasons with list rest from the lexer" do
    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> {error, {7, opengql_lexer, <<\"bad lexer\">>}, \"tail\"}.
        """
      },
      fn ->
        assert {:error, "bad lexer", "tail", %{}, 7, 0} = Parser.parse("ignored")
      end
    )
  end

  test "normalizes binary reasons from parser four-tuple errors" do
    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> {ok, [], 1}.
        """,
        opengql_parser: """
        -module(opengql_parser).
        -export([parse/1]).
        parse(_Tokens) -> {error, {5, opengql_parser, <<\"bad parse\">>, token}}.
        """
      },
      fn ->
        assert {:error, "bad parse", "", %{}, 5, 0} = Parser.parse("ignored")
      end
    )
  end

  test "normalizes list reasons into binaries" do
    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> {error, {6, opengql_lexer, ["list", " reason"]}, <<"tail">>}.
        """
      },
      fn ->
        assert {:error, "list reason", "tail", %{}, 6, 0} = Parser.parse("ignored")
      end
    )
  end

  test "normalizes non-string reasons via inspect" do
    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> {error, {8, opengql_lexer, atom_reason}, <<"tail">>}.
        """
      },
      fn ->
        assert {:error, ":atom_reason", "tail", %{}, 8, 0} = Parser.parse("ignored")
      end
    )
  end

  test "normalizes binary rest values and unexpected return shapes" do
    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> {error, {4, opengql_lexer, <<\"bad binary rest\">>}, <<\"rest\">>}.
        """
      },
      fn ->
        assert {:error, "bad binary rest", "rest", %{}, 4, 0} = Parser.parse("ignored")
      end
    )

    with_stubbed_modules(
      %{
        opengql_lexer: """
        -module(opengql_lexer).
        -export([string/1]).
        string(_Chars) -> unexpected_result.
        """
      },
      fn ->
        assert {:error, ":unexpected_result", "", %{}, 1, 0} = Parser.parse("ignored")
      end
    )
  end

  defp with_stubbed_modules(module_sources, fun) do
    originals =
      Enum.into(module_sources, %{}, fn {module_name, _source} ->
        {module_name, :code.get_object_code(module_name)}
      end)

    temp_dir = Path.join(System.tmp_dir!(), "opengql_parser_wrapper_#{System.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)

    try do
      Enum.each(module_sources, fn {module_name, source} ->
        compile_and_load_stub(module_name, source, temp_dir)
      end)

      fun.()
    after
      Enum.each(module_sources, fn {module_name, _source} ->
        unload_module(module_name)

        case Map.fetch!(originals, module_name) do
          {^module_name, binary, filename} ->
            :code.load_binary(module_name, filename, binary)

          _ ->
            :ok
        end
      end)

      File.rm_rf!(temp_dir)
    end
  end

  defp compile_and_load_stub(module_name, source, temp_dir) do
    unload_module(module_name)

    file_path = Path.join(temp_dir, Atom.to_string(module_name) <> ".erl")
    File.write!(file_path, source)

    assert {:ok, ^module_name, binary} =
             :compile.file(String.to_charlist(file_path), [:binary, :report_errors])

    assert {:module, ^module_name} =
             :code.load_binary(module_name, String.to_charlist(file_path), binary)
  end

  defp unload_module(module_name) do
    :code.purge(module_name)
    :code.delete(module_name)
  end
end
