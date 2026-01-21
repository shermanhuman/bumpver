defmodule Bumpver.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/shermanhuman/bumpver"

  def project do
    [
      app: :bumpver,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Bumpver",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Interactive semantic version management for Elixir projects.
    Provides Mix tasks to bump versions and verify version changes before commits.
    """
  end

  defp package do
    [
      name: "bumpver",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}"
    ]
  end
end
