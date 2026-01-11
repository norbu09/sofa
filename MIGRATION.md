# Tesla to Req Migration Guide

## Summary of Changes

Sofa has been successfully migrated from Tesla to Req HTTP client. This migration brings better performance, simpler configuration, and modern HTTP/2 support.

## What Changed

### Dependencies

**Before:**
```elixir
# mix.exs
{:tesla, "~> 1.4"},
{:gun, "~> 2.0.0-rc.1", override: true, optional: true}
```

**After:**
```elixir
# mix.exs
{:req, ">= 0.5.8"},
{:jason, "~> 1.4"}
```

### Configuration

**Before:**
```elixir
# config/config.exs
import Config

if config_env() == :test do
  config :tesla, adapter: Tesla.Mock
else
  config :tesla, adapter: Tesla.Adapter.Gun
end
```

**After:**
```elixir
# config/config.exs
import Config

# Req configuration
# Req handles HTTP adapters automatically, no additional configuration needed
```

### Internal Changes

All Tesla-specific code has been replaced with Req equivalents:

1. **Client Creation:** `Tesla.client()` → `Req.new()`
2. **Requests:** `Tesla.request()` → `Req.request()`
3. **Response Handling:** Tesla.Env → Req.Response
4. **Authentication:** Tesla middleware → Req's built-in `:auth` option

## Breaking Changes

### ⚠️ None for Public API

The public API remains **100% compatible**. All existing code using Sofa should continue to work without changes.

### Internal Changes Only

If you were directly accessing internal Sofa structs:

**Before:**
```elixir
%Sofa{client: %Tesla.Client{...}}
```

**After:**
```elixir
%Sofa{client: %Req.Request{...}}
```

## Benefits of Req

1. **Simpler Configuration:** No adapter configuration needed
2. **Better Performance:** Built-in connection pooling
3. **Modern Features:** HTTP/2 support out of the box
4. **Active Development:** More actively maintained
5. **Smaller Dependency Tree:** Fewer transitive dependencies

## Testing Changes

### Old Approach (Tesla.Mock)

```elixir
import Tesla.Mock

setup do
  mock(fn
    %{method: :get, url: url} ->
      %Tesla.Env{status: 200, body: %{}}
  end)
  :ok
end
```

### New Approach (Integration Tests)

Sofa now uses real integration tests against a CouchDB instance:

```elixir
# Unit tests run by default
mix test

# Integration tests (require running CouchDB)
mix test --include integration
```

**To run integration tests:**
```bash
# Start CouchDB (Docker)
docker run -d -p 5984:5984 -e COUCHDB_USER=admin -e COUCHDB_PASSWORD=passwd couchdb:3

# Run tests
mix test --include integration
```

## Migration Steps

If you're using Sofa in your project:

### Step 1: Update Dependencies

```bash
mix deps.update sofa
mix deps.get
```

### Step 2: Update Configuration (if needed)

Remove any Tesla-specific configuration:

```elixir
# Remove this:
config :tesla, adapter: Tesla.Adapter.Gun

# No Req configuration needed
```

### Step 3: Verify Tests Pass

```bash
mix test
```

### Step 4: Update to Latest Version

```elixir
# mix.exs
{:sofa, github: "norbu09/sofa", branch: "main"}
```

## Troubleshooting

### Issue: Tests failing with Tesla errors

**Solution:** Make sure you've pulled the latest version:
```bash
mix deps.clean sofa
mix deps.get
mix compile --force
```

### Issue: Connection errors

**Solution:** Req uses Finch under the hood. If you need custom connection pool settings:
```elixir
# This is handled automatically, but if needed:
# Req will use sensible defaults
```

### Issue: Slow requests

**Solution:** Req handles connection pooling automatically. If you're creating a new Sofa client for each request, reuse the client instead:

```elixir
# Bad (creates new connection each time)
def get_doc(id) do
  Sofa.init(...) |> Sofa.client() |> Sofa.Doc.get(id)
end

# Good (reuse client)
def get_doc(sofa, id) do
  Sofa.Doc.get(sofa, id)
end
```

## Questions?

- **Issues:** https://github.com/norbu09/sofa/issues
- **Discussions:** https://github.com/norbu09/sofa/discussions

---

**Last Updated:** 2026-01-11
