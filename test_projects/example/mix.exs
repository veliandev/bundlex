defmodule Example.MixProject do
  use Mix.Project

  def project do
    [
      app: :example,
      version: "0.1.0",
      elixir: "~> 1.10",
      compilers: [:bundlex] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bundlex, path: "../.."},
      {:example_lib, path: "../example_lib"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "pages/doxygen/example.md"
      ]
    ]
  end
end
