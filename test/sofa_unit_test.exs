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
  end
end
