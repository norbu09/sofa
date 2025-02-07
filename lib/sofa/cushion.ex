defmodule Sofa.Cushion do
  require Logger

  @moduledoc """
  Internal Helpers for Sofa, with a vanity naming convention.

  > If the only tool you have is CouchDB, everything is very
  > uncomfortable without a Cushion.
  """

  @doc """
  Sanitise HTTP headers into ones we trust and format, and drop the rest.
  This is necessary because proxies, clients, HTTP1* and HTTP2 all disagree
  about whether headers should be upper, lower, camel, snake, or wtf case.

  Server : CouchDB/3.1.1 (Erlang OTP/22)
  X-Couch-Request-Id : f5b74b7038
  X-Couchdb-Body-Time : 0
  Cache-Control : must-revalidate
  Content-Length : 443
  Content-Type : application/json
  Date : Sun, 25 Apr 2021 18:43:36 GMT
  Etag : "4-322add00c33cab838bf9d7909f18d4f5"

  """
  @spec untaint_headers(map()) :: map()
  def untaint_headers(h) when is_map(h) do
    Enum.reduce(h, %{}, fn x, acc ->
      {k, v} = untaint_header(x)
      Map.put(acc, k, v)
    end)
  end

  defp untaint_header({"etag", [v]}) do
    {:etag, String.trim(v, ~s("))}
  end

  defp untaint_header({"cache-control", [v]}) do
    {:cache_control, String.downcase(v)}
  end

  defp untaint_header({"server", [v]}) do
    {:server, String.downcase(v)}
  end

  defp untaint_header({"x-couch-request-id", [v]}) do
    {:couch_request_id, v}
  end

  defp untaint_header({"date", [v]}) do
    {:date, v}
  end

  defp untaint_header({"location", [v]}) do
    {:location, v}
  end

  defp untaint_header({"content-type", [v]}) do
    {:content_type, String.downcase(v)}
  end

  defp untaint_header({"content-length", [v]}) do
    {:content_length, String.to_integer(v)}
  end

  defp untaint_header({"x-couchdb-body-time", [v]}) do
    {:couchdb_body_time, String.to_integer(v)}
  end

  defp untaint_header({"connection", [v]}) do
    {:connection, String.downcase(v)}
  end

  defp untaint_header({k, [v]}) do
    {String.downcase(k), v}
  end
end
