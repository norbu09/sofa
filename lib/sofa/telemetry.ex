defmodule Sofa.Telemetry do
  @moduledoc """
  Telemetry integration for Sofa CouchDB client.

  This module provides telemetry events for monitoring and observability
  of CouchDB operations.

  ## Events

  All events are published under the `[:sofa, :request]` namespace with
  the following suffixes:

  - `[:sofa, :request, :start]` - Emitted when a request starts
  - `[:sofa, :request, :stop]` - Emitted when a request completes successfully
  - `[:sofa, :request, :exception]` - Emitted when a request fails

  ## Event Measurements

  ### Start Event
  - `:system_time` - The system time when the request started
  - `:monotonic_time` - Monotonic time when the request started

  ### Stop Event
  - `:duration` - The time spent executing the request (native time units)
  - `:monotonic_time` - Monotonic time when the request completed
  - `:status` - HTTP status code

  ### Exception Event
  - `:duration` - The time spent before the exception (native time units)
  - `:monotonic_time` - Monotonic time when the exception occurred

  ## Event Metadata

  All events include the following metadata:

  - `:method` - HTTP method (:get, :post, :put, :delete, etc.)
  - `:path` - Request path
  - `:database` - Database name (if applicable)
  - `:doc_id` - Document ID (if applicable)
  - `:operation` - Operation type (:db_create, :doc_get, :view_query, etc.)

  ## Usage

  Attach handlers to the telemetry events to monitor your CouchDB operations:

      :telemetry.attach(
        "sofa-request-logger",
        [:sofa, :request, :stop],
        &MyApp.Telemetry.handle_request/4,
        %{}
      )

      def handle_request(_event, measurements, metadata, _config) do
        Logger.info("CouchDB request completed",
          method: metadata.method,
          path: metadata.path,
          duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond),
          status: measurements.status
        )
      end

  ## Integration with Telemetry.Metrics

      # In your application telemetry module
      def metrics do
        [
          # Request duration histogram
          Telemetry.Metrics.distribution(
            "sofa.request.duration",
            unit: {:native, :millisecond},
            tags: [:method, :operation, :status]
          ),

          # Request count
          Telemetry.Metrics.counter(
            "sofa.request.count",
            tags: [:method, :operation, :status]
          ),

          # Error count
          Telemetry.Metrics.counter(
            "sofa.request.exception.count",
            tags: [:method, :operation, :kind, :reason]
          )
        ]
      end
  """

  require Logger

  @doc """
  Execute a function with telemetry instrumentation.

  ## Examples

      Sofa.Telemetry.span(:doc_get, %{database: "mydb", doc_id: "doc1"}, fn ->
        # Perform CouchDB operation
        {:ok, result}
      end)
  """
  @spec span(atom(), map(), fun()) :: any()
  def span(operation, metadata, func) do
    start_time = System.monotonic_time()
    start_metadata = Map.put(metadata, :operation, operation)

    :telemetry.execute(
      [:sofa, :request, :start],
      %{monotonic_time: start_time, system_time: System.system_time()},
      start_metadata
    )

    try do
      result = func.()

      stop_time = System.monotonic_time()
      duration = stop_time - start_time

      measurements = %{
        duration: duration,
        monotonic_time: stop_time
      }

      # Extract status from result if available
      measurements =
        case result do
          {:ok, %Sofa.Response{status: status}} -> Map.put(measurements, :status, status)
          {:ok, _sofa, %Sofa.Response{status: status}} -> Map.put(measurements, :status, status)
          _ -> measurements
        end

      :telemetry.execute(
        [:sofa, :request, :stop],
        measurements,
        start_metadata
      )

      result
    rescue
      exception ->
        stop_time = System.monotonic_time()
        duration = stop_time - start_time

        :telemetry.execute(
          [:sofa, :request, :exception],
          %{duration: duration, monotonic_time: stop_time},
          Map.merge(start_metadata, %{
            kind: :error,
            reason: exception,
            stacktrace: __STACKTRACE__
          })
        )

        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Emit a custom telemetry event for Sofa operations.

  ## Examples

      Sofa.Telemetry.event(:bulk_insert, %{count: 100}, %{database: "mydb"})
  """
  @spec event(atom(), map(), map()) :: :ok
  def event(event_name, measurements, metadata) do
    :telemetry.execute(
      [:sofa, event_name],
      measurements,
      metadata
    )
  end

  @doc """
  List all available telemetry events.
  """
  @spec events() :: list(list(atom()))
  def events do
    [
      [:sofa, :request, :start],
      [:sofa, :request, :stop],
      [:sofa, :request, :exception]
    ]
  end

  @doc """
  Attach a simple logger handler to all Sofa telemetry events.

  This is useful for development and debugging.

  ## Examples

      Sofa.Telemetry.attach_default_logger()
  """
  @spec attach_default_logger() :: :ok | {:error, :already_exists}
  def attach_default_logger do
    :telemetry.attach_many(
      "sofa-default-logger",
      events(),
      &handle_event/4,
      %{log_level: :debug}
    )
  end

  @doc """
  Detach the default logger handler.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach("sofa-default-logger")
  end

  # Private event handler
  defp handle_event([:sofa, :request, :start], measurements, metadata, config) do
    log_level = Map.get(config, :log_level, :debug)

    Logger.log(log_level, "Sofa request started",
      operation: metadata[:operation],
      method: metadata[:method],
      path: metadata[:path],
      system_time: measurements[:system_time]
    )
  end

  defp handle_event([:sofa, :request, :stop], measurements, metadata, config) do
    log_level = Map.get(config, :log_level, :debug)
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)

    Logger.log(log_level, "Sofa request completed",
      operation: metadata[:operation],
      method: metadata[:method],
      path: metadata[:path],
      status: measurements[:status],
      duration_ms: duration_ms
    )
  end

  defp handle_event([:sofa, :request, :exception], measurements, metadata, config) do
    log_level = Map.get(config, :log_level, :error)
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)

    Logger.log(log_level, "Sofa request failed",
      operation: metadata[:operation],
      method: metadata[:method],
      path: metadata[:path],
      kind: metadata[:kind],
      reason: inspect(metadata[:reason]),
      duration_ms: duration_ms
    )
  end
end
