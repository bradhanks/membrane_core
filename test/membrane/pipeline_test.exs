defmodule Membrane.PipelineTest do
  use ExUnit.Case

  @module Membrane.Pipeline

  alias Membrane.Pipeline.{Spec, State}

  defp state(_ctx) do
    [state: %State{module: nil, clock_proxy: nil}]
  end

  setup_all :state

  describe "Handle init" do
    test "valid pipeline" do
      defmodule ValidPipeline do
        use Membrane.Pipeline

        @impl true
        def handle_init(_), do: {:error, :reason}
      end

      assert_raise Membrane.CallbackError, fn ->
        @module.init(ValidPipeline)
      end
    end

    test "should raise an error if handle_init raises an error" do
      defmodule InvalidPipeline do
        use Membrane.Pipeline

        @impl true
        def handle_init(_) do
          spec = %Membrane.Pipeline.Spec{}
          {{:ok, spec}, %{}}
        end
      end

      assert {:ok, state} = @module.init(InvalidPipeline)

      assert %Membrane.Pipeline.State{
               internal_state: %{},
               module: InvalidPipeline
             } = state
    end
  end

  describe "handle_action spec" do
    test "should raise if duplicate elements exist in spec", %{state: state} do
      assert_raise Membrane.PipelineError, ~r/.*duplicate.*\[:a\]/i, fn ->
        @module.handle_action(
          {:spec, %Spec{children: [a: :child1, a: :child2]}},
          nil,
          [],
          state
        )
      end
    end

    test "should raise if trying to spawn element with already taken name", %{state: state} do
      state = %State{state | children: %{a: self()}}

      assert_raise Membrane.PipelineError, ~r/.*duplicate.*\[:a\]/i, fn ->
        @module.handle_action(
          {:spec, %Spec{children: [a: :child]}},
          nil,
          [],
          state
        )
      end
    end
  end
end
