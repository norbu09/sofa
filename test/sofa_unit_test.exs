defmodule SofaUnitTest do
  use ExUnit.Case, async: true

  describe "Sofa.init/1" do
    test "init with default URL returns expected struct" do
      sofa = Sofa.init()
      assert sofa.auth == "admin:passwd"
      assert sofa.features == nil
      assert sofa.uri.host == "localhost"
      assert sofa.uri.port == 5984
      assert sofa.uri.scheme == "http"
      assert sofa.uri.userinfo == "admin:passwd"
    end

    test "init with custom URL" do
      sofa = Sofa.init("https://user:pass@example.com:6984/")
      assert sofa.auth == "user:pass"
      assert sofa.uri.host == "example.com"
      assert sofa.uri.port == 6984
      assert sofa.uri.scheme == "https"
      assert sofa.uri.userinfo == "user:pass"
    end

    test "init with URI struct" do
      uri = URI.parse("http://test:secret@db.local:5984/")
      sofa = Sofa.init(uri)
      assert sofa.auth == "test:secret"
      assert sofa.uri.host == "db.local"
    end
  end

  describe "Sofa.client/1" do
    test "creates Req client from Sofa struct" do
      sofa = Sofa.init("http://admin:passwd@localhost:5984/") |> Sofa.client()
      assert is_struct(sofa.client, Req.Request)
      assert sofa.database == nil
    end

    test "creates Req client with database" do
      sofa =
        Sofa.init("http://admin:passwd@localhost:5984/")
        |> Sofa.client("mydb")

      assert is_struct(sofa.client, Req.Request)
      assert sofa.database == "mydb"
    end
  end

  describe "Sofa.auth_info/1" do
    test "parses valid user:password" do
      assert Sofa.auth_info("admin:password") == %{username: "admin", password: "password"}
    end

    test "parses user with empty password" do
      assert Sofa.auth_info("blank:") == %{username: "blank", password: ""}
    end

    test "returns empty map for invalid input" do
      assert Sofa.auth_info("garbage") == %{}
      assert Sofa.auth_info("") == %{}
      assert Sofa.auth_info(nil) == %{}
    end
  end

  describe "Sofa.Doc" do
    test "new/1 creates empty doc with ID" do
      doc = Sofa.Doc.new("test-id")
      assert doc.id == "test-id"
      assert doc.body == %{}
      assert doc.rev == ""
    end

    test "new/1 creates doc from map with ID" do
      doc = Sofa.Doc.new(%{id: "test-id"})
      assert doc.id == "test-id"
      assert doc.body == %{}
    end

    test "new/1 creates doc from map with ID and body" do
      doc = Sofa.Doc.new(%{id: "test-id", body: %{"key" => "value"}})
      assert doc.id == "test-id"
      assert doc.body == %{"key" => "value"}
    end

    test "to_map/1 converts doc to CouchDB format" do
      doc = %Sofa.Doc{
        id: "test-id",
        rev: "1-abc",
        body: %{"foo" => "bar"},
        type: nil,
        attachments: nil
      }

      map = Sofa.Doc.to_map(doc)
      assert map["_id"] == "test-id"
      assert map["_rev"] == "1-abc"
      assert map["foo"] == "bar"
    end

    test "from_map/1 converts CouchDB format to doc (with underscores)" do
      map = %{
        "_id" => "test-id",
        "_rev" => "1-abc",
        "foo" => "bar"
      }

      doc = Sofa.Doc.from_map(map)
      assert doc.id == "test-id"
      assert doc.rev == "1-abc"
      assert doc.body == %{"foo" => "bar"}
    end

    test "from_map/1 converts CouchDB format to doc (without underscores)" do
      map = %{
        "id" => "test-id",
        "rev" => "1-abc",
        "foo" => "bar"
      }

      doc = Sofa.Doc.from_map(map)
      assert doc.id == "test-id"
      assert doc.rev == "1-abc"
      assert doc.body == %{"foo" => "bar"}
    end
  end

  describe "Sofa.View" do
    test "from_map/1 parses view response" do
      response = %Sofa.Response{
        body: %{
          "total_rows" => 10,
          "offset" => 0,
          "rows" => [
            %{"key" => "key1", "value" => %{"count" => 5}},
            %{"key" => "key2", "value" => %{"count" => 3}}
          ]
        },
        status: 200,
        method: :get
      }

      view = Sofa.View.from_map(response)
      assert view.total_rows == 10
      assert view.offset == 0
      assert length(view.rows) == 2
    end

    test "prepare_view_opts/1 handles boolean options" do
      opts = [include_docs: true, descending: false, reduce: true]
      result = Sofa.View.prepare_view_opts(opts)

      assert Keyword.get(result, :include_docs) == true
      assert Keyword.get(result, :descending) == false
      assert Keyword.get(result, :reduce) == true
    end

    test "prepare_view_opts/1 handles numeric options" do
      opts = [limit: 10, skip: 5, group_level: 2]
      result = Sofa.View.prepare_view_opts(opts)

      assert Keyword.get(result, :limit) == 10
      assert Keyword.get(result, :skip) == 5
      assert Keyword.get(result, :group_level) == 2
    end

    test "prepare_view_opts/1 handles stale options" do
      opts_ok = [stale: :ok]
      result_ok = Sofa.View.prepare_view_opts(opts_ok)
      assert Keyword.get(result_ok, :stale) == "ok"

      opts_update = [stale: :update_after]
      result_update = Sofa.View.prepare_view_opts(opts_update)
      assert Keyword.get(result_update, :stale) == "update_after"
    end

    test "prepare_view_opts/1 encodes key options as JSON" do
      opts = [
        key: "simple_string",
        startkey: "start",
        endkey: ["complex", "key"]
      ]

      result = Sofa.View.prepare_view_opts(opts)
      assert Keyword.get(result, :key) == ~s("simple_string")
      assert Keyword.get(result, :startkey) == ~s("start")
      assert Keyword.get(result, :endkey) == ~s(["complex","key"])
    end
  end

  describe "Sofa.Bulk" do
    test "parse_bulk_results/1 handles successful results" do
      results = [
        %{"ok" => true, "id" => "doc1", "rev" => "1-abc"},
        %{"ok" => true, "id" => "doc2", "rev" => "1-def"}
      ]

      parsed = Sofa.Bulk.parse_bulk_results(results)
      assert length(parsed) == 2
      assert Enum.at(parsed, 0) == %{ok: true, id: "doc1", rev: "1-abc"}
      assert Enum.at(parsed, 1) == %{ok: true, id: "doc2", rev: "1-def"}
    end

    test "parse_bulk_results/1 handles error results" do
      results = [
        %{"ok" => true, "id" => "doc1", "rev" => "1-abc"},
        %{"error" => "conflict", "id" => "doc2", "reason" => "Document update conflict"}
      ]

      parsed = Sofa.Bulk.parse_bulk_results(results)
      assert length(parsed) == 2
      assert Enum.at(parsed, 0) == %{ok: true, id: "doc1", rev: "1-abc"}

      error = Enum.at(parsed, 1)
      assert error.error == "conflict"
      assert error.id == "doc2"
      assert error.reason == "Document update conflict"
    end
  end

  describe "Sofa.Error" do
    test "NotFound.exception/1 creates error with message" do
      error = Sofa.Error.NotFound.exception(doc_id: "test-doc", database: "test-db")
      assert error.doc_id == "test-doc"
      assert error.database == "test-db"
      assert error.status == 404
      assert error.message == "Document 'test-doc' not found in database 'test-db'"
    end

    test "Conflict.exception/1 creates error with revisions" do
      error =
        Sofa.Error.Conflict.exception(
          doc_id: "test-doc",
          current_rev: "2-xyz",
          attempted_rev: "1-abc"
        )

      assert error.doc_id == "test-doc"
      assert error.current_rev == "2-xyz"
      assert error.attempted_rev == "1-abc"
      assert error.status == 409
      assert error.message =~ "conflict"
    end

    test "from_response/2 creates NotFound error for 404" do
      body = %{"error" => "not_found", "reason" => "missing"}
      error = Sofa.Error.from_response(404, body, doc_id: "test-doc")

      assert %Sofa.Error.NotFound{} = error
      assert error.status == 404
      assert error.doc_id == "test-doc"
    end

    test "from_response/2 creates Conflict error for 409" do
      body = %{"error" => "conflict", "reason" => "Document update conflict"}
      error = Sofa.Error.from_response(409, body)

      assert %Sofa.Error.Conflict{} = error
      assert error.status == 409
    end

    test "from_response/2 creates Unauthorized error for 401" do
      body = %{"error" => "unauthorized", "reason" => "Name or password is incorrect"}
      error = Sofa.Error.from_response(401, body)

      assert %Sofa.Error.Unauthorized{} = error
      assert error.status == 401
    end

    test "from_response/2 creates Forbidden error for 403" do
      body = %{"error" => "forbidden", "reason" => "Insufficient permissions"}
      error = Sofa.Error.from_response(403, body)

      assert %Sofa.Error.Forbidden{} = error
      assert error.status == 403
    end

    test "from_response/2 creates BadRequest error for 400" do
      body = %{"error" => "bad_request", "reason" => "Invalid JSON"}
      error = Sofa.Error.from_response(400, body)

      assert %Sofa.Error.BadRequest{} = error
      assert error.status == 400
      assert error.details == body
    end

    test "from_response/2 creates ServerError for 500+" do
      body = %{"error" => "internal_server_error", "reason" => "Something went wrong"}
      error = Sofa.Error.from_response(500, body)

      assert %Sofa.Error.ServerError{} = error
      assert error.status == 500
    end
  end

  describe "Sofa.Telemetry" do
    test "events/0 returns list of telemetry events" do
      events = Sofa.Telemetry.events()
      assert is_list(events)
      assert [:sofa, :request, :start] in events
      assert [:sofa, :request, :stop] in events
      assert [:sofa, :request, :exception] in events
    end

    test "span/3 executes function and emits telemetry" do
      # Attach a test handler
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(pid, {ref, event, measurements, metadata})
      end

      :telemetry.attach_many(
        "test-handler-#{inspect(ref)}",
        Sofa.Telemetry.events(),
        handler,
        %{}
      )

      # Execute a function within telemetry span
      result =
        Sofa.Telemetry.span(:test_operation, %{database: "test"}, fn ->
          {:ok, :test_result}
        end)

      assert result == {:ok, :test_result}

      # Verify start event was emitted
      assert_received {^ref, [:sofa, :request, :start], start_measurements, start_metadata}
      assert is_integer(start_measurements.monotonic_time)
      assert start_metadata.operation == :test_operation
      assert start_metadata.database == "test"

      # Verify stop event was emitted
      assert_received {^ref, [:sofa, :request, :stop], stop_measurements, stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_metadata.operation == :test_operation

      # Cleanup
      :telemetry.detach("test-handler-#{inspect(ref)}")
    end
  end
end
