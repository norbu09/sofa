# Exclude integration tests by default unless --include integration is passed
ExUnit.start(exclude: [:integration])

# Helper module for test fixtures
defmodule TestHelper do
  def fixture(f), do: File.read!("test/fixtures/" <> f) |> Jason.decode!()
end
