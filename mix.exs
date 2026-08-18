defmodule Tuix.MixProject do
  use Mix.Project

  @version "0.1.6"
  @source_url "https://github.com/ryanwinchester/tuix"

  def project do
    [
      app: :tuix,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An OpenTUI-inspired terminal UI framework for Elixir",
      package: package(),
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
      {:ucwidth, "~> 0.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "guides/packaging.md"],
      source_url: @source_url,
      source_ref: "master"
    ]
  end
end
