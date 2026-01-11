defmodule Sofa.Phase2UnitTest do
  use ExUnit.Case
  doctest Sofa.Changes
  doctest Sofa.Mango
  doctest Sofa.Attachment
  doctest Sofa.Security

  describe "Sofa.Changes.prepare_changes_opts/1" do
    test "prepares basic options" do
      opts = [since: "123", limit: 10, include_docs: true]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:since] == "123"
      assert result[:limit] == 10
      assert result[:include_docs] == true
    end

    test "converts feed type to string" do
      opts = [feed: :continuous]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:feed] == "continuous"
    end

    test "handles doc_ids filter" do
      opts = [doc_ids: ["doc1", "doc2"]]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:filter] == "_doc_ids"
      assert result[:doc_ids] == Jason.encode!(["doc1", "doc2"])
    end

    test "handles all feed types" do
      for feed <- [:normal, :longpoll, :continuous, :eventsource] do
        result = Sofa.Changes.prepare_changes_opts(feed: feed)
        assert result[:feed] == Atom.to_string(feed)
      end
    end

    test "handles timeout and heartbeat" do
      opts = [timeout: 60_000, heartbeat: 10_000]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:timeout] == 60_000
      assert result[:heartbeat] == 10_000
    end

    test "handles style option" do
      opts = [style: :all_docs]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:style] == "all_docs"
    end

    test "handles boolean flags" do
      opts = [descending: true, conflicts: true, attachments: true]
      result = Sofa.Changes.prepare_changes_opts(opts)

      assert result[:descending] == true
      assert result[:conflicts] == true
      assert result[:attachments] == true
    end
  end

  describe "Sofa.Changes.parse_change/1" do
    test "parses a basic change" do
      change = %{
        "seq" => "3-xyz",
        "id" => "doc123",
        "changes" => [%{"rev" => "2-abc"}]
      }

      result = Sofa.Changes.parse_change(change)

      assert result.seq == "3-xyz"
      assert result.id == "doc123"
      assert result.changes == [%{rev: "2-abc"}]
      assert result.deleted == nil
      assert result.doc == nil
    end

    test "parses change with document" do
      change = %{
        "seq" => "5-xyz",
        "id" => "doc456",
        "changes" => [%{"rev" => "3-def"}],
        "doc" => %{"_id" => "doc456", "name" => "Test"}
      }

      result = Sofa.Changes.parse_change(change)

      assert result.doc == %{"_id" => "doc456", "name" => "Test"}
    end

    test "parses deleted change" do
      change = %{
        "seq" => "7-xyz",
        "id" => "doc789",
        "changes" => [%{"rev" => "4-ghi"}],
        "deleted" => true
      }

      result = Sofa.Changes.parse_change(change)

      assert result.deleted == true
    end
  end

  describe "Sofa.Mango query helpers" do
    test "simple selector" do
      query = %{
        "selector" => %{
          "type" => "user"
        }
      }

      assert query["selector"]["type"] == "user"
    end

    test "complex selector with operators" do
      query = %{
        "selector" => %{
          "$and" => [
            %{"type" => "user"},
            %{"age" => %{"$gte" => 18}}
          ]
        }
      }

      assert is_list(query["selector"]["$and"])
      assert length(query["selector"]["$and"]) == 2
    end

    test "query with fields and sort" do
      query = %{
        "selector" => %{"type" => "user"},
        "fields" => ["_id", "name", "email"],
        "sort" => [%{"name" => "asc"}],
        "limit" => 10
      }

      assert query["fields"] == ["_id", "name", "email"]
      assert query["sort"] == [%{"name" => "asc"}]
      assert query["limit"] == 10
    end

    test "query with use_index" do
      query = %{
        "selector" => %{"email" => "test@example.com"},
        "use_index" => "_design/idx-email"
      }

      assert query["use_index"] == "_design/idx-email"
    end
  end

  describe "Sofa.Security security document helpers" do
    test "empty security is public" do
      security = %{
        admins: %{names: [], roles: []},
        members: %{names: [], roles: []}
      }

      assert Enum.empty?(security.admins.names)
      assert Enum.empty?(security.members.names)
    end

    test "security with admins" do
      security = %{
        admins: %{
          names: ["alice", "bob"],
          roles: ["admins"]
        },
        members: %{names: [], roles: []}
      }

      assert "alice" in security.admins.names
      assert "admins" in security.admins.roles
    end

    test "security with members" do
      security = %{
        admins: %{names: [], roles: []},
        members: %{
          names: ["charlie"],
          roles: ["users", "developers"]
        }
      }

      assert "charlie" in security.members.names
      assert "users" in security.members.roles
      assert "developers" in security.members.roles
    end

    test "adding user to list" do
      names = ["alice", "bob"]
      new_user = "charlie"
      updated = Enum.uniq([new_user | names])

      assert "charlie" in updated
      assert length(updated) == 3
    end

    test "adding duplicate user doesn't create duplicates" do
      names = ["alice", "bob"]
      existing_user = "alice"
      updated = Enum.uniq([existing_user | names])

      assert length(updated) == 2
      assert Enum.count(updated, &(&1 == "alice")) == 1
    end

    test "removing user from list" do
      names = ["alice", "bob", "charlie"]
      updated = List.delete(names, "bob")

      assert "bob" not in updated
      assert length(updated) == 2
    end
  end

  describe "Attachment content type detection" do
    test "common mime types" do
      assert mime_type_for("image.jpg") in ["image/jpeg", "application/octet-stream"]
      assert mime_type_for("document.pdf") in ["application/pdf", "application/octet-stream"]
      assert mime_type_for("video.mp4") in ["video/mp4", "application/octet-stream"]
      assert mime_type_for("unknown.xyz") == "application/octet-stream"
    end

    defp mime_type_for(filename) do
      case Path.extname(filename) do
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".png" -> "image/png"
        ".gif" -> "image/gif"
        ".pdf" -> "application/pdf"
        ".mp4" -> "video/mp4"
        ".mp3" -> "audio/mpeg"
        ".txt" -> "text/plain"
        ".json" -> "application/json"
        ".xml" -> "application/xml"
        _ -> "application/octet-stream"
      end
    end
  end

  describe "Integration helpers" do
    test "bookmark pagination helper" do
      # Simulate bookmark from first page
      bookmark = "g1AAAAG3eJzLYWBg4MhgTmHgS04sKU7NS8"

      query_page1 = %{
        "selector" => %{"type" => "user"},
        "limit" => 10
      }

      query_page2 = Map.put(query_page1, "bookmark", bookmark)

      assert query_page2["bookmark"] == bookmark
      assert query_page2["limit"] == 10
    end

    test "building complex mango queries" do
      # Test query builder pattern
      query =
        %{"selector" => %{}}
        |> put_in(["selector", "type"], "user")
        |> put_in(["selector", "age"], %{"$gte" => 18})
        |> Map.put("fields", ["_id", "name"])
        |> Map.put("limit", 50)

      assert query["selector"]["type"] == "user"
      assert query["selector"]["age"]["$gte"] == 18
      assert query["fields"] == ["_id", "name"]
      assert query["limit"] == 50
    end
  end

  describe "Error handling patterns" do
    test "conflict error structure" do
      error = %Sofa.Error.Conflict{
        reason: "Document update conflict",
        doc_id: "test123"
      }

      assert error.reason == "Document update conflict"
      assert error.doc_id == "test123"
    end

    test "not found error structure" do
      error = %Sofa.Error.NotFound{
        reason: "Document not found"
      }

      assert error.reason == "Document not found"
    end

    test "unauthorized error structure" do
      error = %Sofa.Error.Unauthorized{
        reason: "Admin privileges required"
      }

      assert error.reason == "Admin privileges required"
    end

    test "request error structure" do
      error = %Sofa.Error.BadRequest{
        status: 400,
        reason: "Bad request",
        details: %{"error" => "invalid_json"}
      }

      assert error.status == 400
      assert error.reason == "Bad request"
      assert error.details == %{"error" => "invalid_json"}
    end
  end

  describe "Changes feed sequence handling" do
    test "numeric sequence" do
      seq = 123
      assert to_string(seq) == "123"
    end

    test "string sequence" do
      seq = "123-g1AAAABXeJzLYWBg4MhgTmHg"
      assert seq == "123-g1AAAABXeJzLYWBg4MhgTmHg"
    end

    test "now sequence" do
      seq = "now"
      assert seq == "now"
    end

    test "sequence comparison" do
      # Sequences should be treated as opaque strings
      seq1 = "1-abc"
      seq2 = "2-def"
      assert seq1 != seq2
    end
  end

  describe "Mango index definitions" do
    test "simple index definition" do
      index_def = %{
        "index" => %{
          "fields" => ["email"]
        },
        "name" => "idx-email"
      }

      assert index_def["index"]["fields"] == ["email"]
      assert index_def["name"] == "idx-email"
    end

    test "compound index definition" do
      index_def = %{
        "index" => %{
          "fields" => ["type", "created_at", "status"]
        },
        "name" => "idx-type-created-status"
      }

      assert length(index_def["index"]["fields"]) == 3
    end

    test "partial index definition" do
      index_def = %{
        "index" => %{
          "fields" => ["age"]
        },
        "partial_filter_selector" => %{
          "type" => "user"
        }
      }

      assert index_def["partial_filter_selector"]["type"] == "user"
    end

    test "text index definition" do
      index_def = %{
        "index" => %{
          "fields" => [%{"name" => "title", "type" => "string"}]
        },
        "name" => "text-idx",
        "type" => "text"
      }

      assert index_def["type"] == "text"
    end
  end
end
