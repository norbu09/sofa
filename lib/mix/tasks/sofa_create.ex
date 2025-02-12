defmodule Mix.Tasks.Sofa.Create do
  use Mix.Task
  require Logger

  @shortdoc "Creates the repository storage"

  @switches [
    quiet: :boolean,
    db: :string
  ]

  @aliases [
    q: :quiet
  ]

  @moduledoc """
  Create the storage for repos in all resources for the given (or configured) DBs.

  ## Examples

      mix sofa.create
      mix sofa.create --db my_couch

  ## Command line options

    * `--db` - the database you want to create
    * `--quiet` - do not log output
  """

  @doc false
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    case opts do
      [db: db] ->
        # TODO: this needs to parse the config and init the init function
        # also, we may need to start quite a bit of the app for this to make it work i think
        Sofa.init()
        |> Sofa.client()
        |> Sofa.DB.create(db)
    end

    Logger.debug("Creating database: #{inspect(opts)}")
  end
end
