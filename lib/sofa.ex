defmodule Sofa do
  @moduledoc """
  Documentation for `Sofa`, a test-driven idiomatic Apache CouchDB client.

  > If the only tool you have is CouchDB, then
  > everything looks like {:ok, :relax}

  ## Examples

  iex> Sofa.init() |> Sofa.client() |> Sofa.connect!()
  %{
    "couchdb" => "Welcome",
    "features" => ["access-ready", "partitioned", "pluggable-storage-engines", "reshard", "scheduler"],
    "git_sha" => "ce596c65d",
    "uuid" => "59c032d3a6adcd5b44315137a124bf69",
    "vendor" => %{"name" => "FreeBSD"},
    "version" => "3.1.1"
  }
  """

  @derive {Inspect, except: [:auth]}
  defstruct [
    # auth specific headers such as Bearer, Basic
    :auth,
    # re-usable req HTTP client
    :client,
    # optional database field
    :database,
    # feature response as returned from CouchDB `GET /`
    :features,
    # optional timeout for CouchDB-specific responses
    :timeout,
    # %URI parsed
    :uri,
    # uuid as reported from CouchDB `GET /`
    :uuid,
    # vendor-specific info as reported from CouchDB `GET /`
    :vendor,
    # CouchDB's API version
    :version
  ]

  @type t :: %__MODULE__{
          auth: any,
          client: nil | Req.Request.t(),
          database: nil | binary,
          features: nil | list,
          timeout: nil | integer,
          uri: nil | URI.t(),
          uuid: nil | binary,
          vendor: nil | map,
          version: nil | binary
        }

  require Logger

  # these default credentials are also used in CouchDB integration tests
  # because CouchDB3+ no longer accepts "admin party" blank credentials
  @default_uri "http://admin:passwd@localhost:5984/"

  @doc """
  Takes an optional parameter, the CouchDB uri, and returns a struct
  containing the usual CouchDB server properties. The URI may be given
  as a string or as a %URI struct.

  This should be piped into Sofa.client/1 to create the HTTP client,
  which is stored inside the struct with correct authentication information.

  ## Examples

  iex> Sofa.init("https://very:Secure@foreignho.st:6984/")
  %Sofa{
    auth: "very:Secure",
    features: nil,
    uri: %URI{
      authority: "very:Secure@foreignho.st:6984",
      fragment: nil,
      host: "foreignho.st",
      path: "/",
      port: 6984,
      query: nil,
      scheme: "https",
      userinfo: "very:Secure"
    },
    uuid: nil,
    vendor: nil,
    version: nil
  }

  """
  # TODO: we want to have this in our config:
  #
  # config :my_app, MyApp.Sofa.RepoOne,
  #   uri: "http://localhost:5984/db1",
  #   name: :db1,
  #   user: "admin",
  #   pass: "admin"
  #
  # config :my_app, MyApp.Sofa.RepoTwo,
  #   uri: "http://localhost:5984/db2",
  #   name: :db2,
  #   user: "admin",
  #   pass: "admin"
  #
  # config :couchdb, repos: [Databases.RepoOne, Databases.RepoTwo],
  #   default: MyApp.Sofa.RepoOne
  #
  @spec init() :: Sofa.t()
  def init do
    case Application.get_env(:couchdb, :default) do
      nil ->
        @default_uri

      db ->
        db.init()
    end
  end

  @spec init(uri :: String.t() | URI.t()) :: Sofa.t()
  def init(uri) do
    uri = URI.parse(uri)

    %Sofa{
      auth: uri.userinfo,
      uri: uri
    }
  end

  @doc """
  Builds Telsa runtime client, with appropriate middleware header credentials,
  from supplied %Sofa{} struct.
  """
  @spec client(Sofa.t()) :: Sofa.t()
  def client(couch = %Sofa{uri: uri}) do
    couch_url = uri.scheme <> "://" <> uri.host <> ":#{uri.port}/"

    client =
      Req.new(
        base_url: couch_url,
        auth: {:basic, uri.userinfo},
        headers: [{"Content-Type", "application/json"}]
      )

    %Sofa{couch | client: client}
  end

  @doc """
  Returns user & password credentials extracted from a typical %URI{} userinfo
  field, as a Tesla-compatible authorization header. Currently only supports
  BasicAuth user:password combination.
  ## Examples

  iex> Sofa.auth_info("admin:password")
  %{username: "admin", password: "password"}

  iex> Sofa.auth_info("blank:")
  %{username: "blank", password: ""}

  iex> Sofa.auth_info("garbage")
  %{}
  """
  @spec auth_info(nil | String.t()) :: %{} | %{user: String.t(), password: String.t()}
  def auth_info(nil), do: %{}

  def auth_info(info) when is_binary(info) do
    case String.split(info, ":", parts: 2) do
      [""] -> %{}
      ["", _] -> %{}
      [user, password] -> %{username: user, password: password}
      _ -> %{}
    end
  end

  @doc """
  Given an existing %Sofa{} struct, or a prepared URI, attempts to connect
  to the CouchDB instance, and returns an updated %Sofa{} to use in future
  connections to this server, using the same HTTP credentials.

  Returns an updated `{:ok, %Sofa{}}` on success, or `{:error, reason}`, if
  for example, the URL is unreachable, times out, supplied credentials are
  rejected by CouchDB, or returns unexpected HTTP status codes.
  """
  @spec connect(String.t() | Sofa.t()) :: {:ok, Sofa.t()} | {:error, any()}
  def connect(sofa) when is_binary(sofa) do
    init(sofa) |> client() |> connect()
  end

  def connect(couch = %Sofa{}) do
    case result = Req.get(couch.client, url: "/") do
      {:error, _} ->
        result

      {:ok, resp} ->
        {:ok,
         %Sofa{
           couch
           | features: resp.body["features"],
             uuid: resp.body["uuid"],
             vendor: resp.body["vendor"],
             version: resp.body["version"]
         }}
    end
  end

  @doc """
  Bang! wrapper around Sofa.connect/1; raises exceptions on error.
  """
  @spec connect!(String.t() | Sofa.t()) :: Sofa.t()
  def connect!(sofa) when is_binary(sofa) do
    init(sofa) |> client() |> connect!()
  end

  def connect!(sofa = %Sofa{}) when is_struct(sofa, Sofa) do
    url = sofa.uri.host <> ":" <> to_string(sofa.uri.port)

    case connect(sofa) do
      {:error, %Req.TransportError{reason: :econnrefused}} ->
        raise Sofa.Error, "connection refused to " <> url

      {:ok, resp} ->
        resp

      _ ->
        raise Sofa.Error, "unhandled error from " <> url
    end
  end

  @doc """
  List all databases. Only available to admin users.
  """
  @spec all_dbs(Sofa.t()) :: {:error, any()} | {:ok, Sofa.t(), [String.t()]}
  def all_dbs(sofa = %Sofa{}) do
    case raw(sofa, "_all_dbs") do
      {:error, reason} ->
        {:error, reason}

      {:ok, _sofa, resp} ->
        {:ok, resp.body}
    end
  end

  @doc """
  Get _active_tasks. Only available to admin users.
  """
  @spec active_tasks(Sofa.t()) :: {:error, any()} | {:ok, Sofa.t(), [String.t()]}
  def active_tasks(sofa = %Sofa{}) do
    case raw(sofa, "active_tasks") do
      {:error, reason} -> {:error, reason}
      {:ok, _sofa, resp} -> {:ok, resp.body}
    end
  end

  @doc """
  Minimal wrapper around native CouchDB HTTP API, allowing an escape hatch
  for raw functionality, and as the core abstraction layer for Sofa itself.
  """
  # FIXME: fix type specs
  @spec raw(
          Sofa.t(),
          String.t(),
          atom(),
          list(),
          map()
        ) ::
          {:error, any()} | {:ok, Sofa.t(), %Sofa.Response{}}
  def raw(
        sofa = %Sofa{},
        path \\ "",
        method \\ :get,
        query \\ [],
        body \\ %{}
      ) do
    # each Tesla adapter handles "empty" options differently - some
    # expect nil, others "", and some expect the key:value to be missing
    body_data = Jason.encode_to_iodata!(body)

    case Req.request(sofa.client, url: path, method: method, params: query, body: body_data) do
      {:ok, resp = %{body: %{"error" => _error, "reason" => _reason}}} ->
        {:error,
         %Sofa.Response{
           body: resp.body,
           url: path,
           query: query,
           method: method,
           headers: Sofa.Cushion.untaint_headers(resp.headers),
           status: resp.status
         }}

      {:ok, %{} = resp} ->
        {:ok, sofa,
         %Sofa.Response{
           body: resp.body,
           url: path,
           query: query,
           method: method,
           headers: Sofa.Cushion.untaint_headers(resp.headers),
           status: resp.status
         }}

      _ ->
        Logger.debug("unhandled error in #{method} #{path}")
        raise Sofa.Error, "unhandled error in #{method} #{path}"
    end
  end

  @doc """
  Bang! wrapper around Sofa.raw/1; raises exceptions on error.
  """
  @spec raw!(
          Sofa.t(),
          Tesla.Env.url(),
          Tesla.Env.method(),
          Tesla.Env.opts(),
          Tesla.Env.body()
        ) :: %Sofa.Response{}
  def raw!(sofa = %Sofa{}, path \\ "", method \\ :get, query \\ [], body \\ %{}) do
    case raw(sofa, path, method, query, body) do
      {:ok, %Sofa{}, response = %Sofa.Response{}} -> response
      {:error, _reason} -> raise(Sofa.Error, "unhandled error in #{method} #{path}")
    end
  end

  ##### public interface #######
  ###
  #
  # not sure yet if i want to use this ...

  @doc """
  The public interface to couch should be as simple as possible, something along these lines:

  iex> Sofa.get(sofa, "/foo/bar")
  iex> Sofa.get(sofa, "/foo")
  iex> Sofa.get(sofa, db: "foo", id: "bar")
  iex> Sofa.get(sofa, db: "foo")
  iex> Sofa.get(sofa, db: "foo", view: "map/foo")
  iex> Sofa.get(sofa, db: "foo", view: "map/foo", reduce: true)

  ideally we also want a way to call the init function implicitly and configure it via the config system so that we get this:

  iex> Sofa.get("/foo/bar")

  """

  def get(sofa = %Sofa{database: nil}, path) when is_binary(path) do
    case String.trim_leading(path, "/") |> String.split("/", parts: 2) do
      [db, id] ->
        Sofa.Doc.get(%Sofa{sofa | database: db}, id)

      [db] ->
        Sofa.DB.info(sofa, db)

      _ ->
        {:error, :db_not_found}
    end
  end

  def get(sofa = %Sofa{database: db}, path) when is_binary(path) do
    id = String.trim_leading(path, "/")
    Sofa.Doc.get(%Sofa{sofa | database: db}, id)
  end

  def get(sofa = %Sofa{database: nil}, opts) when is_list(opts) do
    case Keyword.keys(opts) do
      [:db, :id] ->
        Sofa.Doc.get(%Sofa{sofa | database: Keyword.get(opts, :db)}, Keyword.get(opts, :id))

      [:db] ->
        Sofa.DB.info(sofa, Keyword.get(opts, :db))

      _ ->
        {:error, :db_not_found}
    end
  end
end
