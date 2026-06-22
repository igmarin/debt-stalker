defmodule DebtStalkerWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Hammer (ETS backend).

  Limits requests per client IP on a sliding window. Exceeding the
  limit returns `429 Too Many Requests` with a `Retry-After` header
  and a JSON error body.

  ## Configuration

  Limits are configured in `config.exs` under `:debt_stalker, :rate_limit`
  and can be overridden via env vars in `runtime.exs`:

      config :debt_stalker, :rate_limit,
        auth_token: [limit: 10, window_ms: 60_000],
        webhook: [limit: 20, window_ms: 60_000]

  ## Usage

      plug DebtStalkerWeb.Plugs.RateLimit, [key: :auth_token] when action == :create
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @spec init(keyword()) :: keyword()
  def init(opts) do
    # Validate that :key is present. Config is read at runtime in
    # call/2 so that env vars from runtime.exs are respected.
    _ = Keyword.fetch!(opts, :key)
    opts
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    key = Keyword.fetch!(opts, :key)
    config = Application.get_env(:debt_stalker, :rate_limit)[key]

    unless config do
      raise ArgumentError, "Rate limit config not found for key: #{inspect(key)}"
    end

    limit = Keyword.fetch!(config, :limit)
    window_ms = Keyword.fetch!(config, :window_ms)

    client_ip = get_client_ip(conn)
    bucket = "#{key}:#{client_ip}"

    case Hammer.check_rate(bucket, window_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        retry_after = div(window_ms, 1000)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(429)
        |> json(%{"error" => "rate_limit_exceeded"})
        |> halt()
    end
  end

  @spec get_client_ip(Plug.Conn.t()) :: String.t()
  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [header | _] when is_binary(header) and header != "" ->
        # X-Forwarded-For is a comma-separated list of proxy IPs;
        # the leftmost is the original client IP.
        header
        |> String.split(",")
        |> List.first()
        |> String.trim()

      _ ->
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "unknown"
        end
    end
  end
end
