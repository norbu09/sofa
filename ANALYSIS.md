# Sofa Library - Functionality Analysis & Development Plan

## Executive Summary

Sofa is an Elixir client library for Apache CouchDB that has been successfully migrated from Tesla to Req HTTP client. The library provides an idiomatic Elixir interface for CouchDB operations with a focus on simplicity and Repo-style patterns.

## Current State (January 2026)

### ✅ Completed Features

#### 1. **HTTP Client Layer**
- ✅ Successfully migrated from Tesla to Req
- ✅ Basic authentication support (username:password)
- ✅ Automatic JSON encoding/decoding
- ✅ Connection pooling (handled by Req)
- ✅ Header sanitization and normalization

#### 2. **Server Operations** (`Sofa` module)
- ✅ Connection management (`connect/1`, `connect!/1`)
- ✅ Server information retrieval
- ✅ Feature flags detection
- ✅ Database listing (`all_dbs/1`)
- ✅ Active tasks monitoring (`active_tasks/1`)
- ✅ Raw API access for custom operations

#### 3. **Database Operations** (`Sofa.DB` module)
- ✅ Create database
- ✅ Delete database
- ✅ Get database info
- ✅ Open database (with permission checks)
- ✅ Database existence checks

#### 4. **Document Operations** (`Sofa.Doc` module)
- ✅ Document creation (with/without ID)
- ✅ Document retrieval
- ✅ Document updates
- ✅ Document deletion
- ✅ Document existence checks
- ✅ Map conversion (to/from CouchDB format)
- ✅ Proper handling of `_id` and `_rev` fields

#### 5. **Design Documents** (`Sofa.DDoc` module)
- ✅ Design document creation
- ✅ Design document retrieval
- ✅ Design document updates
- ✅ Design document listing
- ✅ View definition management

#### 6. **View Operations** (`Sofa.View` module)
- ✅ Basic view querying
- ✅ `_all_docs` support
- ✅ Include docs option
- ✅ View results parsing
- ⚠️  Query options (limited)

#### 7. **Repository Pattern** (`Sofa.Repo` module)
- ✅ Configuration-based initialization
- ✅ Application-level database clients
- ✅ Convenience methods (get_doc, create_doc, etc.)
- ✅ OTP app integration

#### 8. **Testing Infrastructure**
- ✅ Unit tests (21 passing tests)
- ✅ Integration test structure (tagged for real CouchDB)
- ✅ Test fixtures
- ✅ Clean separation of unit vs integration tests

---

## ⚠️ Partially Implemented Features

### 1. **View Querying** (60% complete)
**Current State:**
- Basic queries work
- Include docs works
- Results parsing works

**Missing:**
- Advanced query options (startkey, endkey, limit, skip)
- Reduce function support
- Group and group_level options
- Key and keys filtering
- Descending order
- Stale options

**Example of what's needed:**
```elixir
# Not yet supported:
Sofa.View.get(sofa, "design/view",
  startkey: "2024-01-01",
  endkey: "2024-12-31",
  limit: 100,
  reduce: false
)
```

### 2. **Document Attachments** (0% complete)
**Current State:**
- Struct has `attachments` field
- No implementation

**Needed:**
- Attachment upload
- Attachment download
- Inline attachments
- Multipart support
- Content-type handling

### 3. **Type System / Struct Protocol** (10% complete)
**Current State:**
- `type` field exists in Doc struct
- Comments suggest future protocol implementation

**Vision:**
```elixir
defmodule MyApp.User do
  @derive {Sofa.Document, database: "users"}
  defstruct [:name, :email, :created_at]
end

# Should work seamlessly:
user = %MyApp.User{name: "Alice", email: "alice@example.com"}
{:ok, saved_user} = Sofa.Doc.create(sofa, user)
```

---

## ❌ Missing Features

### 1. **Changes Feed** (Priority: HIGH)
CouchDB's changes feed is critical for real-time applications.

**Needed:**
- Normal changes feed
- Continuous changes feed
- Filter support
- Since parameter
- Include docs option
- Heartbeat support

```elixir
# Proposed API:
Sofa.Changes.get(sofa, db,
  since: "now",
  feed: :continuous,
  filter: "mydesign/myfilter"
)
```

### 2. **Mango Queries** (Priority: HIGH)
Modern CouchDB uses Mango for JSON queries.

**Needed:**
- `_find` endpoint support
- Index creation
- Query execution
- Selector syntax

```elixir
# Proposed API:
Sofa.Find.query(sofa, db, %{
  selector: %{
    "type" => "user",
    "age" => %{"$gt" => 21}
  },
  sort: [%{"age" => "asc"}],
  limit: 10
})
```

### 3. **Bulk Operations** (Priority: MEDIUM)
**Needed:**
- Bulk document creation
- Bulk document updates
- Bulk document deletion
- `_bulk_docs` endpoint

```elixir
# Proposed API:
docs = [%{foo: 1}, %{bar: 2}, %{baz: 3}]
Sofa.Doc.create_bulk(sofa, docs)
```

### 4. **Replication** (Priority: MEDIUM)
**Needed:**
- Replication trigger
- Replication monitoring
- Replication configuration

### 5. **Security** (Priority: MEDIUM)
**Needed:**
- Database security document management
- Admin users/roles
- Member users/roles
- Bearer token auth (OAuth)
- Cookie-based auth

### 6. **Partitioned Databases** (Priority: LOW)
CouchDB 3+ supports partitioned databases.

**Needed:**
- Partition-aware document IDs
- Partition queries
- Partition-specific views

### 7. **Performance Features** (Priority: LOW)
**Needed:**
- Request timeouts (partially exists)
- Retry logic (Req provides some)
- Connection pooling configuration
- Request tracing/telemetry

---

## Code Quality & Architecture

### Strengths
✅ Clean module separation
✅ Consistent error handling (`{:ok, ...}` / `{:error, ...}`)
✅ Bang! versions for convenience
✅ Good use of pattern matching
✅ Type specs throughout
✅ Well-documented modules

### Areas for Improvement

1. **Error Handling**
   - Current: Basic error tuples
   - Needed: More specific error types
   ```elixir
   {:error, %Sofa.Error{type: :not_found, reason: "Document not found", doc_id: "abc"}}
   ```

2. **Logging**
   - Current: Some debug logging
   - Needed: Structured logging with metadata
   - Needed: Configurable log levels

3. **Telemetry**
   - Current: None
   - Needed: `:telemetry` events for monitoring
   ```elixir
   :telemetry.execute(
     [:sofa, :request, :stop],
     %{duration: duration},
     %{method: :get, path: "/db/doc"}
   )
   ```

4. **Documentation**
   - Current: Good module docs, some function docs
   - Needed: More examples
   - Needed: Usage guides
   - Needed: Migration guide (Tesla → Req)

5. **Testing**
   - Current: Good unit test coverage
   - Needed: More integration tests
   - Needed: Property-based tests
   - Needed: Performance benchmarks

---

## Development Roadmap

### Phase 1: Core Stability (1-2 months)
**Goal:** Production-ready core features

1. ✅ Complete Tesla → Req migration
2. ⬜ Add comprehensive error types
3. ⬜ Implement telemetry events
4. ⬜ Add timeout configuration
5. ⬜ Complete view query options
6. ⬜ Add bulk operations
7. ⬜ Improve test coverage to 90%+

### Phase 2: Essential Features (2-3 months)
**Goal:** Support common CouchDB workflows

1. ⬜ Implement Changes feed
2. ⬜ Implement Mango queries
3. ⬜ Add attachment support
4. ⬜ Implement security document management
5. ⬜ Add database replication triggers
6. ⬜ Create migration tools (mix tasks)

### Phase 3: Advanced Features (3-4 months)
**Goal:** Enterprise-ready features

1. ⬜ Struct/Protocol implementation
2. ⬜ Ecto adapter (investigate feasibility)
3. ⬜ Ash framework integration
4. ⬜ Partitioned database support
5. ⬜ Advanced auth (OAuth, Cookie)
6. ⬜ Performance optimization
7. ⬜ Comprehensive benchmarks

### Phase 4: Ecosystem Integration (Ongoing)
**Goal:** Make Sofa the go-to CouchDB client

1. ⬜ Hex.pm publication
2. ⬜ Complete documentation site
3. ⬜ Tutorial series
4. ⬜ Example applications
5. ⬜ Community building
6. ⬜ CI/CD pipeline
7. ⬜ Release automation

---

## Immediate Next Steps (This Week)

### High Priority
1. **Add view query options**
   ```elixir
   # Support these options:
   - startkey / endkey
   - limit / skip
   - descending
   - include_docs (already done)
   - reduce / group / group_level
   ```

2. **Implement bulk operations**
   ```elixir
   Sofa.Doc.bulk_create/2
   Sofa.Doc.bulk_update/2
   Sofa.Doc.bulk_delete/2
   ```

3. **Add proper error types**
   ```elixir
   defmodule Sofa.Error do
     defexception [:type, :reason, :status, :metadata]

     # Types:
     # :not_found, :conflict, :unauthorized, :timeout, etc.
   end
   ```

4. **Create mix tasks for migrations**
   ```bash
   mix sofa.db.create my_db
   mix sofa.db.migrate
   mix sofa.ddoc.push design_doc.json
   ```

### Medium Priority
1. **Add telemetry**
   - Request duration
   - Success/failure counts
   - Connection pool stats

2. **Improve documentation**
   - Add more @doc examples
   - Create guides/ directory
   - Document migration from Tesla

3. **Enhanced testing**
   - Add property-based tests (StreamData)
   - Integration test suite with Docker Compose
   - Performance benchmarks

---

## Technical Debt

### Must Fix
- ⬜ Remove old test files (.old extension)
- ✅ Update all Tesla references in docs (DONE)
- ⬜ Add CHANGELOG.md
- ⬜ Version bump to reflect breaking changes

### Should Fix
- ⬜ Consistent parameter ordering across modules
- ⬜ Better naming for `raw` function (maybe `request`?)
- ⬜ Simplify `from_map` / `to_map` logic in Doc
- ⬜ Extract header normalization to dedicated module

### Nice to Have
- ⬜ Generate docs with ex_doc
- ⬜ Add dialyzer to CI
- ⬜ Add credo to CI
- ⬜ Set up GitHub Actions

---

## Dependencies Analysis

### Current Dependencies
```elixir
{:req, ">= 0.5.8"}        # HTTP client (GOOD)
{:jason, "~> 1.4"}        # JSON codec (STANDARD)
{:idna, ">= 6.1.0"}       # International domain names (OPTIONAL)
{:credo, ">= 1.3.0"}      # Code quality (DEV)
{:dialyxir, ">= 1.1.0"}   # Type checking (DEV)
```

### Recommendations
- ✅ Current deps are minimal and appropriate
- Consider adding:
  - `{:telemetry, "~> 1.0"}` for observability
  - `{:stream_data, "~> 1.0"}` for property testing (dev)
  - `{:ex_doc, "~> 0.31"}` for documentation (dev)

---

## Performance Considerations

### Current Approach
- Req handles connection pooling automatically
- JSON encoding via Jason (fast)
- Minimal allocations in hot paths

### Future Optimizations
1. **Streaming**
   - Stream large attachments
   - Stream changes feed
   - Stream view results

2. **Caching**
   - Cache design documents
   - Cache view definitions
   - Configurable TTL

3. **Batching**
   - Batch document operations
   - Batch view queries

---

## Security Considerations

### Current State
- ✅ Basic auth over HTTPS
- ✅ Credentials in URI (works but not ideal)
- ⚠️  No token-based auth
- ⚠️  No cookie-based auth

### Recommendations
1. Support multiple auth strategies:
   ```elixir
   # Basic auth (current)
   Sofa.init("http://user:pass@localhost:5984")

   # Token auth (proposed)
   Sofa.init("http://localhost:5984", auth: {:bearer, token})

   # Cookie auth (proposed)
   Sofa.init("http://localhost:5984", auth: {:cookie, cookie})
   ```

2. Never log credentials
3. Support credential rotation
4. Warn on HTTP (non-HTTPS) in production

---

## Community & Ecosystem

### Current State
- Not published to Hex.pm yet
- GitHub repo exists (norbu09/sofa)
- Minimal documentation
- No known users besides author

### Growth Strategy
1. **Documentation First**
   - Complete API documentation
   - Write guides for common tasks
   - Create video tutorials

2. **Example Applications**
   - Todo app with LiveView
   - Blog engine
   - Real-time chat
   - Analytics dashboard

3. **Integration Examples**
   - Phoenix integration
   - Ecto integration (if feasible)
   - Ash integration
   - Oban integration (for job queues)

4. **Community Building**
   - ElixirForum post
   - Blog post announcing Req migration
   - Conference talk proposal
   - Open issues for contributors

---

## Conclusion

Sofa is a promising CouchDB client that has successfully modernized its HTTP layer by migrating to Req. The core functionality is solid, with good patterns and clean code.

### Key Strengths
- Clean, idiomatic Elixir code
- Modern HTTP client (Req)
- Good separation of concerns
- Repository pattern support

### Main Gaps
- Missing Changes feed (critical for real-time apps)
- No Mango query support (modern CouchDB)
- Limited attachment support
- No bulk operations

### Recommended Focus
1. **Short term:** Complete view options, add bulk operations, improve docs
2. **Medium term:** Changes feed, Mango queries, attachments
3. **Long term:** Ecto/Ash integration, advanced features

With focused development over the next 3-6 months, Sofa could become the de facto CouchDB client for Elixir.

---

## Appendix: API Examples

### Basic Usage
```elixir
# Connect
sofa = Sofa.init("http://admin:password@localhost:5984")
       |> Sofa.client()
       |> Sofa.connect!()

# Database operations
{:ok, db, _resp} = Sofa.DB.create(sofa, "mydb")
{:ok, db_info} = Sofa.DB.info(db, "mydb")

# Document operations
{:ok, doc} = Sofa.Doc.create(db, "doc_id", %{name: "Alice", age: 30})
{:ok, doc} = Sofa.Doc.get(db, "doc_id")
{:ok, updated} = Sofa.Doc.update(db, %{doc | body: Map.put(doc.body, "age", 31)})
{:ok, _} = Sofa.Doc.delete(db, doc.id, doc.rev)

# View operations
{:ok, view} = Sofa.View.get(db, "design/view_name")
{:ok, docs} = Sofa.View.all_docs(db, include_docs: true)
```

### Repository Pattern
```elixir
# config/config.exs
config :my_app, MyApp.CouchDB,
  base_uri: "http://localhost:5984",
  database: "my_app_db",
  username: "admin",
  password: "password"

# lib/my_app/couch_db.ex
defmodule MyApp.CouchDB do
  use Sofa.Repo, otp_app: :my_app
end

# Usage
MyApp.CouchDB.create_doc(%{name: "Bob", email: "bob@example.com"})
MyApp.CouchDB.get_doc("doc_id")
MyApp.CouchDB.get_view("mydesign/myview")
```

---

**Generated:** 2026-01-11
**Author:** Claude (Analysis Assistant)
**Status:** Living Document - Update as development progresses
