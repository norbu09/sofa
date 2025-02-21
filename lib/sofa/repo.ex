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

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger

      @conf Application.compile_env(opts[:otp_app], __MODULE__)

      def client do
        case @conf do
          nil ->
            Logger.error("Could not find configuration for Sofa.Repo")

          conf ->
            uri = URI.parse(conf[:base_uri])
            base_url = "#{uri.scheme}://#{uri.host}:#{uri.port}/"
            db = conf[:database] || uri.path || ""
            auth = "#{conf[:username]}:#{conf[:password]}" || uri.userinfo

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
    end
  end
end
