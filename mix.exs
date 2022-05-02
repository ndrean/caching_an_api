defmodule CachingAnApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :caching_an_api,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {CachingAnApi.Application, []}
      # included_applications: [:mnesia]
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.8"},
      {:poison, "~> 5.0"},
      {:benchee, "~> 1.1"},
      {:jason, "~> 1.3"},
      {:libcluster, "~> 3.3"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
