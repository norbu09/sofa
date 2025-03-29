defmodule Sofa.Repo do
  # The expected config looks like this:
  # config :my_app, MyApp.Sofa.RepoOne,
  #   uri: "http://localhost:5984/db1",
  #   name: :db1,
  #   user: "admin",
  #   pass: "admin"
  #
  #   and we initialise a couchdb with this:
  #   defmodule MyApp.Sofa.RepoOne do
  #   use Sofa.Repo,
  #     otp_app: my_app
  #   end

  defmacro __using__(options) do
    quote do
      require Logger

      def client(opts \\ unquote(options)) do
        case Application.get_env(opts[:otp_app], __MODULE__) do
          nil ->
            Logger.error("Could not find configuration for Sofa.Repo")

          conf ->
            uri = URI.parse(conf[:base_uri])
            base_url = "#{uri.scheme}://#{uri.host}:#{uri.port}/"
            db = conf[:database] || uri.path || ""

            auth =
              case conf[:username] do
                nil ->
                  uri.userinfo

                user ->
                  "#{user}:#{conf[:password]}" || uri.userinfo
              end

            client =
              Req.new(
                base_url: base_url,
                auth: {:basic, auth},
                headers: [{"Content-Type", "application/json"}]
              )

            %Sofa{
              auth: auth,
              client: client,
              database: db |> String.trim_leading("/")
            }
        end
      end

      def get_doc(path) when is_binary(path) do
        client()
        |> Sofa.Doc.get(path)
      end

      def create_doc(doc) when is_map(doc) do
        client()
        |> Sofa.Doc.create(doc)
      end

      def create_doc(path, doc) when is_map(doc) and is_binary(path) do
        client()
        |> Sofa.Doc.create(path, doc)
      end

      def update_doc(%Sofa.Doc{} = doc) do
        client()
        |> Sofa.Doc.update(doc)
      end

      def get_view(path) when is_binary(path), do: get_view(path, [])

      def get_view(path, opts) when is_binary(path) do
        client()
        |> Sofa.View.get(path, opts)
      end

      def delete_doc(%Sofa.Doc{} = doc) do
        client()
        |> Sofa.Doc.delete(doc.id, doc.rev)
      end

      def delete_doc(id, rev) do
        client()
        |> Sofa.Doc.delete(id, rev)
      end
    end
  end
end
