defmodule Sofa.Security do
  @moduledoc """
  CouchDB Database Security API.

  Security documents control access to databases by defining:
  - **Admins** - Can modify the database security object and create design docs
  - **Members** - Can read/write documents (if database is private)

  Users and roles can be specified in the security document.

  ## Security Model

  - If no security document exists, the database is public (anyone can read/write)
  - If a security document exists with members, only members can read/write
  - Admins can always read/write and modify security
  - Server admins bypass all security

  ## Examples

      # Get current security
      {:ok, security} = Sofa.Security.get(sofa, "mydb")

      # Set security (make database private)
      {:ok, _} = Sofa.Security.put(sofa, "mydb", %{
        "admins" => %{
          "names" => ["admin1"],
          "roles" => ["admin_role"]
        },
        "members" => %{
          "names" => ["user1", "user2"],
          "roles" => ["member_role"]
        }
      })

      # Add a user as admin
      {:ok, _} = Sofa.Security.add_admin(sofa, "mydb", "new_admin")

      # Add a role as member
      {:ok, _} = Sofa.Security.add_member_role(sofa, "mydb", "editors")

      # Remove security (make database public again)
      {:ok, _} = Sofa.Security.delete(sofa, "mydb")

  """

  @type security_doc :: %{
          String.t() => %{
            String.t() => [String.t()]
          }
        }

  @doc """
  Get the security document for a database.

  Returns the current security settings including admins and members.

  ## Examples

      {:ok, security} = Sofa.Security.get(sofa, "mydb")

      security.admins.names #=> ["admin1", "admin2"]
      security.admins.roles #=> ["admin_role"]
      security.members.names #=> ["user1"]
      security.members.roles #=> []

  """
  @spec get(Req.Request.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def get(sofa, db_name) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{req | url: URI.append_path(req.url, "/#{db_name}/_security")}
      end
    )
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, parse_security(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Failed to get security",
           
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
  Set the security document for a database.

  Replaces the entire security document. Requires admin privileges.

  ## Security Document Format

      %{
        "admins" => %{
          "names" => ["alice", "bob"],
          "roles" => ["admins"]
        },
        "members" => %{
          "names" => ["charlie"],
          "roles" => ["developers", "users"]
        }
      }

  ## Examples

      # Make database private with specific members
      {:ok, _} = Sofa.Security.put(sofa, "mydb", %{
        "members" => %{
          "roles" => ["users"]
        }
      })

      # Make database admin-only
      {:ok, _} = Sofa.Security.put(sofa, "mydb", %{
        "admins" => %{
          "names" => ["superuser"]
        },
        "members" => %{
          "names" => []
        }
      })

  """
  @spec put(Req.Request.t(), String.t(), security_doc()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def put(sofa, db_name, security_doc) when is_map(security_doc) do
    sofa
    |> Req.Request.append_request_steps(
      put_path: fn req ->
        %{req | url: URI.append_path(req.url, "/#{db_name}/_security")}
      end
    )
    |> Req.put(json: security_doc)
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        {:error,
         %Sofa.Error.Unauthorized{
           reason: "Admin privileges required to modify security"
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Sofa.Error.BadRequest{
           status: status,
           reason: body["reason"] || "Failed to update security",
           
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
  Delete the security document (make database public).

  This removes all security restrictions, making the database readable
  and writable by anyone.

  ## Examples

      {:ok, _} = Sofa.Security.delete(sofa, "mydb")

  """
  @spec delete(Req.Request.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def delete(sofa, db_name) do
    put(sofa, db_name, %{
      "admins" => %{"names" => [], "roles" => []},
      "members" => %{"names" => [], "roles" => []}
    })
  end

  @doc """
  Add a user as an admin to the database.

  ## Examples

      {:ok, _} = Sofa.Security.add_admin(sofa, "mydb", "alice")

  """
  @spec add_admin(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def add_admin(sofa, db_name, username) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:admins, :names], Enum.uniq([username | security.admins.names]))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Add a role as an admin role to the database.

  ## Examples

      {:ok, _} = Sofa.Security.add_admin_role(sofa, "mydb", "superadmins")

  """
  @spec add_admin_role(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def add_admin_role(sofa, db_name, role) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:admins, :roles], Enum.uniq([role | security.admins.roles]))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Add a user as a member of the database.

  ## Examples

      {:ok, _} = Sofa.Security.add_member(sofa, "mydb", "bob")

  """
  @spec add_member(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def add_member(sofa, db_name, username) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:members, :names], Enum.uniq([username | security.members.names]))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Add a role as a member role to the database.

  ## Examples

      {:ok, _} = Sofa.Security.add_member_role(sofa, "mydb", "users")

  """
  @spec add_member_role(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def add_member_role(sofa, db_name, role) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:members, :roles], Enum.uniq([role | security.members.roles]))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Remove a user from admins.

  ## Examples

      {:ok, _} = Sofa.Security.remove_admin(sofa, "mydb", "alice")

  """
  @spec remove_admin(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def remove_admin(sofa, db_name, username) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:admins, :names], List.delete(security.admins.names, username))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Remove a role from admin roles.

  ## Examples

      {:ok, _} = Sofa.Security.remove_admin_role(sofa, "mydb", "superadmins")

  """
  @spec remove_admin_role(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def remove_admin_role(sofa, db_name, role) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:admins, :roles], List.delete(security.admins.roles, role))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Remove a user from members.

  ## Examples

      {:ok, _} = Sofa.Security.remove_member(sofa, "mydb", "bob")

  """
  @spec remove_member(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def remove_member(sofa, db_name, username) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:members, :names], List.delete(security.members.names, username))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Remove a role from member roles.

  ## Examples

      {:ok, _} = Sofa.Security.remove_member_role(sofa, "mydb", "users")

  """
  @spec remove_member_role(Req.Request.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Sofa.Error.t()}
  def remove_member_role(sofa, db_name, role) do
    with {:ok, security} <- get(sofa, db_name) do
      updated =
        security
        |> put_in([:members, :roles], List.delete(security.members.roles, role))
        |> security_to_map()

      put(sofa, db_name, updated)
    end
  end

  @doc """
  Check if a user has admin access to the database.

  Note: This only checks the security document. Server admins always have access
  regardless of the security document.

  ## Examples

      {:ok, is_admin} = Sofa.Security.is_admin?(sofa, "mydb", "alice")
      {:ok, is_admin} = Sofa.Security.is_admin?(sofa, "mydb", "alice", ["admins"])

  """
  @spec is_admin?(Req.Request.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, boolean()} | {:error, Sofa.Error.t()}
  def is_admin?(sofa, db_name, username, roles \\ []) do
    case get(sofa, db_name) do
      {:ok, security} ->
        is_admin =
          username in security.admins.names or
            Enum.any?(roles, fn role -> role in security.admins.roles end)

        {:ok, is_admin}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Check if a user has member access to the database.

  ## Examples

      {:ok, is_member} = Sofa.Security.is_member?(sofa, "mydb", "bob")
      {:ok, is_member} = Sofa.Security.is_member?(sofa, "mydb", "bob", ["users"])

  """
  @spec is_member?(Req.Request.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, boolean()} | {:error, Sofa.Error.t()}
  def is_member?(sofa, db_name, username, roles \\ []) do
    case get(sofa, db_name) do
      {:ok, security} ->
        # If no members are defined, database is public
        if Enum.empty?(security.members.names) and Enum.empty?(security.members.roles) do
          {:ok, true}
        else
          is_member =
            username in security.members.names or
              Enum.any?(roles, fn role -> role in security.members.roles end)

          {:ok, is_member}
        end

      {:error, _} = error ->
        error
    end
  end

  ## Private Functions

  defp parse_security(body) when is_map(body) do
    %{
      admins: %{
        names: get_in(body, ["admins", "names"]) || [],
        roles: get_in(body, ["admins", "roles"]) || []
      },
      members: %{
        names: get_in(body, ["members", "names"]) || [],
        roles: get_in(body, ["members", "roles"]) || []
      }
    }
  end

  defp security_to_map(security) do
    %{
      "admins" => %{
        "names" => security.admins.names,
        "roles" => security.admins.roles
      },
      "members" => %{
        "names" => security.members.names,
        "roles" => security.members.roles
      }
    }
  end
end
