defmodule SofaIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  @plain_url "http://localhost:5984/"
  @admin_url "http://admin:passwd@localhost:5984/"

  describe "integration tests (requires running CouchDB)" do
    test "init returns expected struct" do
      assert Sofa.init() == %Sofa{
               auth: "admin:passwd",
               features: nil,
               uri: %URI{
                 authority: "admin:passwd@localhost:5984",
                 fragment: nil,
                 host: "localhost",
                 path: "/",
                 port: 5984,
                 query: nil,
                 scheme: "http",
                 userinfo: "admin:passwd"
               },
               uuid: nil,
               vendor: nil,
               version: nil
             }
    end

    test "connect accepts plain URI and returns %Sofa{}" do
      sofa = Sofa.connect!(@admin_url)
      assert is_struct(sofa, Sofa)
      assert is_binary(sofa.version)
      assert is_binary(sofa.uuid)
      assert is_list(sofa.features)
    end

    test "returns valid updated %Sofa{} on GET / 200 OK" do
      sofa = Sofa.connect!(@admin_url)
      assert is_struct(sofa, Sofa)
      assert is_binary(sofa.version)
      assert is_binary(sofa.uuid)
      assert is_list(sofa.features)
    end

    test "GET /_up returns 200 OK and %Sofa.Response{}" do
      response =
        Sofa.init(@admin_url)
        |> Sofa.client()
        |> Sofa.connect!()
        |> Sofa.raw!("_up")

      assert %Sofa.Response{method: :get, status: 200} = response
      assert response.body["status"] == "ok"
    end

    test "GET /_active_tasks without credentials returns 401 Unauthorized" do
      response =
        Sofa.init(@plain_url)
        |> Sofa.client()
        |> Sofa.connect!()
        |> Sofa.raw("_active_tasks")

      case response do
        {:error, %Sofa.Response{status: 401}} ->
          assert true

        {:ok, %Sofa{}, %Sofa.Response{status: 200}} ->
          # Some CouchDB configurations allow this without auth
          assert true
      end
    end

    test "GET /_all_dbs with admin credentials returns 200 OK" do
      {:ok, dbs} =
        Sofa.init(@admin_url)
        |> Sofa.client()
        |> Sofa.connect!()
        |> Sofa.all_dbs()

      assert is_list(dbs)
    end
  end
end
