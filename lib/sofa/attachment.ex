defmodule Sofa.Attachment do
  @moduledoc """
  CouchDB Attachments API.

  Attachments allow you to store binary data (images, PDFs, etc.) alongside documents.
  Each attachment has a content type and is identified by a filename.

  ## Storage Methods

  1. **Inline** - Attachment data stored in the document as base64
  2. **Standalone** - Attachment uploaded separately via HTTP

  Standalone attachments are more efficient for large files and streaming.

  ## Examples

      # Upload an attachment
      {:ok, doc} = Sofa.Attachment.put(sofa, "mydb", "doc123",
        "photo.jpg",
        File.read!("photo.jpg"),
        content_type: "image/jpeg"
      )

      # Get an attachment
      {:ok, data} = Sofa.Attachment.get(sofa, "mydb", "doc123", "photo.jpg")
      File.write!("downloaded.jpg", data)

      # List attachments
      {:ok, attachments} = Sofa.Attachment.list(sofa, "mydb", "doc123")

      # Delete an attachment
      {:ok, doc} = Sofa.Attachment.delete(sofa, "mydb", "doc123", "photo.jpg")

      # Get attachment info (without downloading)
      {:ok, info} = Sofa.Attachment.head(sofa, "mydb", "doc123", "photo.jpg")
      info.content_type #=> "image/jpeg"
      info.content_length #=> 1024000

  ## Telemetry Events

  - `[:sofa, :attachment, :upload, :start]` - When upload starts
  - `[:sofa, :attachment, :upload, :stop]` - When upload completes
  - `[:sofa, :attachment, :download, :start]` - When download starts
  - `[:sofa, :attachment, :download, :stop]` - When download completes

  """

  alias Sofa.Telemetry

  @type attachment_info :: %{
          content_type: String.t(),
          length: non_neg_integer(),
          digest: String.t(),
          revpos: pos_integer(),
          stub: boolean()
        }

  @type option ::
          {:content_type, String.t()}
          | {:rev, String.t()}

  @doc """
  Upload an attachment to a document.

  The document doesn't need to exist - it will be created if necessary.
  If the document exists, you must provide the current revision.

  ## Options

  - `:content_type` - MIME type of the attachment (required for new documents)
  - `:rev` - Current document revision (required for existing documents)

  ## Examples

      # Upload to new document
      {:ok, result} = Sofa.Attachment.put(sofa, "photos", "photo:1",
        "image.jpg",
        File.read!("image.jpg"),
        content_type: "image/jpeg"
      )

      # Upload to existing document
      {:ok, result} = Sofa.Attachment.put(sofa, "photos", "photo:1",
        "thumbnail.jpg",
        thumbnail_data,
        content_type: "image/jpeg",
        rev: result.rev
      )

      # Stream upload
      file_stream = File.stream!("large-video.mp4", [], 2048)
      {:ok, result} = Sofa.Attachment.put(sofa, "videos", "video:1",
        "video.mp4",
        file_stream,
        content_type: "video/mp4"
      )

  """
  @spec put(Req.Request.t(), String.t(), String.t(), String.t(), iodata() | Enumerable.t(), [
          option()
        ]) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def put(sofa, db_name, doc_id, filename, data, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    rev = Keyword.get(opts, :rev)

    metadata = %{
      database: db_name,
      doc_id: doc_id,
      filename: filename,
      content_type: content_type
    }

    Telemetry.span([:attachment, :upload], metadata, fn ->
      query_params =
        if rev do
          %{rev: rev}
        else
          %{}
        end

      result =
        sofa
        |> Req.Request.append_request_steps(
          put_path: fn req ->
            %{
              req
              | url:
                  URI.append_path(
                    req.url,
                    "/#{db_name}/#{URI.encode(doc_id)}/#{URI.encode(filename)}"
                  )
            }
          end
        )
        |> Req.put(
          body: data,
          params: query_params,
          headers: [{"content-type", content_type}]
        )
        |> case do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok,
             %{
               ok: body["ok"],
               id: body["id"],
               rev: body["rev"]
             }}

          {:ok, %Req.Response{status: 409, body: body}} ->
            {:error,
             %Sofa.Error.Conflict{
               reason: body["reason"] || "Document update conflict",
               doc_id: doc_id
             }}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Upload failed",
               
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end

      {result, %{status: elem(result, 0)}}
    end)
  end

  @doc """
  Download an attachment from a document.

  Returns the raw binary data of the attachment.

  ## Examples

      {:ok, image_data} = Sofa.Attachment.get(sofa, "photos", "photo:1", "image.jpg")
      File.write!("downloaded.jpg", image_data)

      # Get specific revision
      {:ok, old_image} = Sofa.Attachment.get(sofa, "photos", "photo:1", "image.jpg",
        rev: "2-abc123"
      )

  """
  @spec get(Req.Request.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Sofa.Error.t()}
  def get(sofa, db_name, doc_id, filename, opts \\ []) do
    rev = Keyword.get(opts, :rev)

    metadata = %{
      database: db_name,
      doc_id: doc_id,
      filename: filename
    }

    Telemetry.span([:attachment, :download], metadata, fn ->
      query_params =
        if rev do
          %{rev: rev}
        else
          %{}
        end

      result =
        sofa
        |> Req.Request.append_request_steps(
          put_path: fn req ->
            %{
              req
              | url:
                  URI.append_path(
                    req.url,
                    "/#{db_name}/#{URI.encode(doc_id)}/#{URI.encode(filename)}"
                  )
            }
          end
        )
        |> Req.Request.put_header("accept", "*/*")
        |> Req.get(params: query_params, raw: true)
        |> case do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %Req.Response{status: 404, body: body}} ->
            {:error,
             %Sofa.Error.NotFound{
               reason: body["reason"] || "Attachment not found"
             }}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Download failed",
               
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end

      size = if is_binary(elem(result, 1)), do: byte_size(elem(result, 1)), else: 0
      {result, %{status: elem(result, 0), size: size}}
    end)
  end

  @doc """
  Stream download an attachment.

  Returns a stream that emits chunks of the attachment data.
  Useful for large files to avoid loading entire file into memory.

  ## Examples

      Sofa.Attachment.stream(sofa, "videos", "video:1", "movie.mp4")
      |> Stream.into(File.stream!("downloaded.mp4"))
      |> Stream.run()

  """
  @spec stream(Req.Request.t(), String.t(), String.t(), String.t(), keyword()) ::
          Enumerable.t()
  def stream(sofa, db_name, doc_id, filename, opts \\ []) do
    rev = Keyword.get(opts, :rev)

    query_params =
      if rev do
        %{rev: rev}
      else
        %{}
      end

    Stream.resource(
      fn ->
        # Initialize the stream
        result =
          sofa
          |> Req.Request.append_request_steps(
            put_path: fn req ->
              %{
                req
                | url:
                    URI.append_path(
                      req.url,
                      "/#{db_name}/#{URI.encode(doc_id)}/#{URI.encode(filename)}"
                    )
              }
            end
          )
          |> Req.get(params: query_params, into: :self)

        case result do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            {:ok, result}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error,
             %Sofa.Error.BadRequest{
               status: status,
               reason: body["reason"] || "Stream failed"
             }}

          {:error, exception} ->
            {:error,
             %Sofa.Error.NetworkError{
               reason: Exception.message(exception),
               original_error: exception
             }}
        end
      end,
      fn
        {:ok, {:ok, %Req.Response{body: body}}} when is_binary(body) ->
          {[body], {:ok, :done}}

        {:ok, :done} ->
          {:halt, :done}

        {:error, error} ->
          raise error
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Get attachment metadata without downloading the content.

  Uses HTTP HEAD to retrieve headers only.

  ## Examples

      {:ok, info} = Sofa.Attachment.head(sofa, "photos", "photo:1", "image.jpg")

      info.content_type #=> "image/jpeg"
      info.content_length #=> 1024000
      info.etag #=> "\"2-abc123\""

  """
  @spec head(Req.Request.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def head(sofa, db_name, doc_id, filename) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{
          req
          | url:
              URI.append_path(
                req.url,
                "/#{db_name}/#{URI.encode(doc_id)}/#{URI.encode(filename)}"
              )
        }
      end
    )
    |> Req.head()
    |> case do
      {:ok, %Req.Response{status: status, headers: headers}} when status in 200..299 ->
        {:ok,
         %{
           content_type: get_header(headers, "content-type"),
           content_length: get_header(headers, "content-length") |> String.to_integer(),
           etag: get_header(headers, "etag"),
           content_md5: get_header(headers, "content-md5")
         }}

      {:ok, %Req.Response{status: 404}} ->
        {:error, %Sofa.Error.NotFound{reason: "Attachment not found"}}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: "HEAD request failed"
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  Delete an attachment from a document.

  Requires the current document revision.

  ## Examples

      {:ok, doc} = Sofa.Doc.get(sofa, "photos", "photo:1")

      {:ok, result} = Sofa.Attachment.delete(sofa, "photos", "photo:1",
        "old-image.jpg",
        rev: doc.body["_rev"]
      )

  """
  @spec delete(Req.Request.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def delete(sofa, db_name, doc_id, filename, opts \\ []) do
    rev = Keyword.fetch!(opts, :rev)

    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{
          req
          | url:
              URI.append_path(
                req.url,
                "/#{db_name}/#{URI.encode(doc_id)}/#{URI.encode(filename)}"
              )
        }
      end
    )
    |> Req.delete(params: %{rev: rev})
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok,
         %{
           ok: body["ok"],
           id: body["id"],
           rev: body["rev"]
         }}

      {:ok, %Req.Response{status: 404}} ->
        {:error, %Sofa.Error.NotFound{reason: "Attachment or document not found"}}

      {:ok, %Req.Response{status: 409, body: body}} ->
        {:error,
         %Sofa.Error.Conflict{
           reason: body["reason"] || "Document update conflict",
           doc_id: doc_id
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Delete failed",
           
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  @doc """
  List all attachments for a document.

  Returns a map of attachment names to their metadata.

  ## Examples

      {:ok, attachments} = Sofa.Attachment.list(sofa, "photos", "photo:1")

      attachments
      |> Enum.each(fn {att_name, att_info} ->
        IO.puts("\#{att_name}: \#{att_info.content_type}, \#{att_info.length} bytes")
      end)

  """
  @spec list(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def list(sofa, db_name, doc_id) do
    # Get document to retrieve attachments
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{
          req
          | url: URI.append_path(req.url, "/#{db_name}/#{URI.encode(doc_id)}")
        }
      end
    )
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        attachments = body["_attachments"] || %{}
        {:ok, parse_attachments(attachments)}

      {:ok, %Req.Response{status: 404}} ->
        {:error, %Sofa.Error.NotFound{reason: "Document not found"}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Failed to get document"
         }}

      {:error, exception} ->
        {:error,
         %Sofa.Error.NetworkError{
           reason: Exception.message(exception),
           original_error: exception
         }}
    end
  end

  ## Private Functions

  defp get_header(headers, name) do
    case List.keyfind(headers, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp parse_attachments(attachments) when is_map(attachments) do
    attachments
    |> Enum.map(fn {name, info} ->
      {name,
       %{
         content_type: info["content_type"],
         length: info["length"],
         digest: info["digest"],
         revpos: info["revpos"],
         stub: info["stub"] || false
       }}
    end)
    |> Enum.into(%{})
  end
end
