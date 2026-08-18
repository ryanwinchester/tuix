defmodule Counter.MixProject do
  use Mix.Project

  def project do
    [
      app: :counter,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Counter.Application, []}
    ]
  end

  defp deps do
    [
      {:tuix, path: "../.."},
      {:burrito, "~> 1.6", runtime: false}
    ]
  end

  defp releases do
    [
      counter: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_silicon: maybe_custom_erts(os: :darwin, cpu: :aarch64),
            macos: [os: :darwin, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64],
            linux_arm: [os: :linux, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  # Burrito's precompiled ERTS builds currently ship a beam without working
  # tty support (raw mode / size queries return :enotsup), which breaks
  # keyboard input for TUI apps. Point BURRITO_CUSTOM_ERTS at a local OTP
  # root (e.g. your version manager's install dir) to use its ERTS instead.
  defp maybe_custom_erts(target) do
    case System.get_env("BURRITO_CUSTOM_ERTS") do
      nil -> target
      path -> Keyword.put(target, :custom_erts, path)
    end
  end
end
