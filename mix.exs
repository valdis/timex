defmodule Timex.Mixfile do
  use Mix.Project

  @compile_peg_task "tasks/compile.peg.exs"
  @do_peg_compile?  File.exists?(@compile_peg_task)
  if @do_peg_compile? do
    Code.eval_file @compile_peg_task
  end

  def project do
    [ app: :timex,
      version: "0.12.4",
      elixir: "~> 0.15.1",
      description: "A date/time library for Elixir",
      compilers: compilers(@do_peg_compile?),
      package: package,
      deps: deps(@do_peg_compile?) ]
  end

  def application, do: []

  defp compilers(true), do: [:peg, :erlang, :elixir, :app]
  defp compilers(_),    do: nil

  defp deps(true), do: [{:neotoma, github: "seancribbs/neotoma"}]
  defp deps(_),    do: []

  defp package do
    [ files: ["lib", "priv", "mix.exs", "README.md", "LICENSE.md"],
      contributors: ["Paul Schoenfelder", "Alexei Sholik"],
      licenses: ["MIT"],
      links: [ { "GitHub", "https://github.com/bitwalker/timex" } ] ]
  end
end
