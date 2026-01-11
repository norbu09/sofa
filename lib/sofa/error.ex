defmodule Sofa.Error do
  @moduledoc """
  Error types and error handling for Sofa CouchDB client.

  This module provides structured error types for better error handling
  and debugging when working with CouchDB.

  ## Error Types

  - `Sofa.Error.NotFound` - Document or database not found (404)
  - `Sofa.Error.Conflict` - Document conflict (409)
  - `Sofa.Error.Unauthorized` - Authentication required (401)
  - `Sofa.Error.Forbidden` - Insufficient permissions (403)
  - `Sofa.Error.BadRequest` - Invalid request (400)
  - `Sofa.Error.ServerError` - CouchDB server error (500+)
  - `Sofa.Error.NetworkError` - Network/connection error
  - `Sofa.Error.Unknown` - Other errors

  ## Examples

      case Sofa.Doc.get(sofa, "missing_doc") do
        {:ok, doc} ->
          # Handle success

        {:error, %Sofa.Error.NotFound{} = error} ->
          IO.puts("Document not found: \#{error.message}")

        {:error, %Sofa.Error.Conflict{} = error} ->
          IO.puts("Document conflict: \#{error.message}")

        {:error, error} ->
          IO.puts("Other error: \#{inspect(error)}")
      end
  """

  # Generic Sofa.Error exception for backwards compatibility
  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}

  defmodule NotFound do
    @moduledoc """
    Error raised when a document or database is not found (404).
    """
    defexception [:message, :doc_id, :database, :status, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            doc_id: String.t() | nil,
            database: String.t() | nil,
            status: integer(),
            reason: String.t() | nil
          }

    def exception(opts) do
      doc_id = Keyword.get(opts, :doc_id)
      database = Keyword.get(opts, :database)
      reason = Keyword.get(opts, :reason, "not_found")

      message =
        Keyword.get(opts, :message) ||
          build_message(doc_id, database, reason)

      %__MODULE__{
        message: message,
        doc_id: doc_id,
        database: database,
        status: 404,
        reason: reason
      }
    end

    defp build_message(nil, nil, reason), do: "Not found: #{reason}"
    defp build_message(doc_id, nil, _reason), do: "Document not found: #{doc_id}"
    defp build_message(nil, database, _reason), do: "Database not found: #{database}"

    defp build_message(doc_id, database, _reason),
      do: "Document '#{doc_id}' not found in database '#{database}'"
  end

  defmodule Conflict do
    @moduledoc """
    Error raised when there is a document conflict (409).

    This typically happens when trying to update a document with an
    outdated revision.
    """
    defexception [:message, :doc_id, :current_rev, :attempted_rev, :status, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            doc_id: String.t() | nil,
            current_rev: String.t() | nil,
            attempted_rev: String.t() | nil,
            status: integer(),
            reason: String.t() | nil
          }

    def exception(opts) do
      doc_id = Keyword.get(opts, :doc_id)
      current_rev = Keyword.get(opts, :current_rev)
      attempted_rev = Keyword.get(opts, :attempted_rev)
      reason = Keyword.get(opts, :reason, "conflict")

      message =
        Keyword.get(opts, :message) ||
          build_message(doc_id, current_rev, attempted_rev)

      %__MODULE__{
        message: message,
        doc_id: doc_id,
        current_rev: current_rev,
        attempted_rev: attempted_rev,
        status: 409,
        reason: reason
      }
    end

    defp build_message(nil, _, _), do: "Document conflict"

    defp build_message(doc_id, nil, nil),
      do: "Document conflict for '#{doc_id}'"

    defp build_message(doc_id, _current, nil),
      do: "Document conflict for '#{doc_id}' - revision mismatch"

    defp build_message(doc_id, current, attempted),
      do:
        "Document conflict for '#{doc_id}' - current: #{current}, attempted: #{attempted}"
  end

  defmodule Unauthorized do
    @moduledoc """
    Error raised when authentication is required (401).
    """
    defexception [:message, :status, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            status: integer(),
            reason: String.t() | nil
          }

    def exception(opts) do
      reason = Keyword.get(opts, :reason, "unauthorized")
      message = Keyword.get(opts, :message, "Authentication required")

      %__MODULE__{
        message: message,
        status: 401,
        reason: reason
      }
    end
  end

  defmodule Forbidden do
    @moduledoc """
    Error raised when the operation is forbidden (403).

    This typically happens when the user doesn't have sufficient
    permissions for the requested operation.
    """
    defexception [:message, :status, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            status: integer(),
            reason: String.t() | nil
          }

    def exception(opts) do
      reason = Keyword.get(opts, :reason, "forbidden")
      message = Keyword.get(opts, :message, "Insufficient permissions")

      %__MODULE__{
        message: message,
        status: 403,
        reason: reason
      }
    end
  end

  defmodule BadRequest do
    @moduledoc """
    Error raised when the request is invalid (400).
    """
    defexception [:message, :status, :reason, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            status: integer(),
            reason: String.t() | nil,
            details: map() | nil
          }

    def exception(opts) do
      reason = Keyword.get(opts, :reason, "bad_request")
      details = Keyword.get(opts, :details)
      message = Keyword.get(opts, :message, "Invalid request: #{reason}")

      %__MODULE__{
        message: message,
        status: 400,
        reason: reason,
        details: details
      }
    end
  end

  defmodule ServerError do
    @moduledoc """
    Error raised when CouchDB returns a server error (500+).
    """
    defexception [:message, :status, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            status: integer(),
            reason: String.t() | nil
          }

    def exception(opts) do
      status = Keyword.get(opts, :status, 500)
      reason = Keyword.get(opts, :reason, "internal_server_error")
      message = Keyword.get(opts, :message, "CouchDB server error: #{reason}")

      %__MODULE__{
        message: message,
        status: status,
        reason: reason
      }
    end
  end

  defmodule NetworkError do
    @moduledoc """
    Error raised when there is a network or connection error.
    """
    defexception [:message, :reason, :original_error]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            original_error: any()
          }

    def exception(opts) do
      reason = Keyword.get(opts, :reason, "network_error")
      original_error = Keyword.get(opts, :original_error)
      message = Keyword.get(opts, :message, "Network error: #{reason}")

      %__MODULE__{
        message: message,
        reason: reason,
        original_error: original_error
      }
    end
  end

  defmodule Unknown do
    @moduledoc """
    Error raised for unknown or unexpected errors.
    """
    defexception [:message, :reason, :original_error]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            original_error: any()
          }

    def exception(opts) do
      reason = Keyword.get(opts, :reason)
      original_error = Keyword.get(opts, :original_error)
      message = Keyword.get(opts, :message, "Unknown error")

      %__MODULE__{
        message: message,
        reason: reason,
        original_error: original_error
      }
    end
  end

  @doc """
  Parse a CouchDB error response and return the appropriate error type.

  ## Examples

      iex> Sofa.Error.from_response(404, %{"error" => "not_found", "reason" => "missing"})
      %Sofa.Error.NotFound{status: 404, reason: "missing"}

      iex> Sofa.Error.from_response(409, %{"error" => "conflict"})
      %Sofa.Error.Conflict{status: 409}
  """
  @spec from_response(integer(), map(), Keyword.t()) ::
          NotFound.t()
          | Conflict.t()
          | Unauthorized.t()
          | Forbidden.t()
          | BadRequest.t()
          | ServerError.t()
          | Unknown.t()
  def from_response(status, body, opts \\ [])

  def from_response(404, body, opts) do
    %NotFound{
      message: body["reason"] || "Not found",
      doc_id: Keyword.get(opts, :doc_id),
      database: Keyword.get(opts, :database),
      status: 404,
      reason: body["error"] || body["reason"]
    }
  end

  def from_response(409, body, opts) do
    %Conflict{
      message: body["reason"] || "Document conflict",
      doc_id: Keyword.get(opts, :doc_id),
      status: 409,
      reason: body["error"] || body["reason"]
    }
  end

  def from_response(401, body, _opts) do
    %Unauthorized{
      message: body["reason"] || "Authentication required",
      status: 401,
      reason: body["error"] || body["reason"]
    }
  end

  def from_response(403, body, _opts) do
    %Forbidden{
      message: body["reason"] || "Insufficient permissions",
      status: 403,
      reason: body["error"] || body["reason"]
    }
  end

  def from_response(400, body, _opts) do
    %BadRequest{
      message: body["reason"] || "Bad request",
      status: 400,
      reason: body["error"] || body["reason"],
      details: body
    }
  end

  def from_response(status, body, _opts) when status >= 500 do
    %ServerError{
      message: body["reason"] || "Server error",
      status: status,
      reason: body["error"] || body["reason"]
    }
  end

  def from_response(_status, body, _opts) do
    %Unknown{
      message: body["reason"] || "Unknown error",
      reason: body["error"] || body["reason"],
      original_error: body
    }
  end

  @doc """
  Convert a Req.Response error to a Sofa error.
  """
  @spec from_req_response(Req.Response.t(), Keyword.t()) ::
          NotFound.t()
          | Conflict.t()
          | Unauthorized.t()
          | Forbidden.t()
          | BadRequest.t()
          | ServerError.t()
          | NetworkError.t()
          | Unknown.t()
  def from_req_response(%Req.Response{status: status, body: body}, opts) when is_map(body) do
    from_response(status, body, opts)
  end

  def from_req_response(%Req.Response{status: status, body: body}, opts) do
    # If body is not a map, create a generic error
    from_response(status, %{"error" => "response_error", "reason" => inspect(body)}, opts)
  end

  @doc """
  Convert an exception to a Sofa error.
  """
  @spec from_exception(Exception.t()) :: NetworkError.t() | Unknown.t()
  def from_exception(%Mint.TransportError{} = error) do
    %NetworkError{
      message: "Network transport error: #{Exception.message(error)}",
      reason: "transport_error",
      original_error: error
    }
  end

  def from_exception(error) do
    %Unknown{
      message: "Unexpected error: #{Exception.message(error)}",
      reason: "exception",
      original_error: error
    }
  end
end
