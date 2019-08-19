defmodule Membrane.Testing.Pipeline do
  @moduledoc """
  This Pipeline was created to reduce testing boilerplate and ease communication
  with its elements. It also provides a utility for informing testing process about
  playback state changes and received notifications.

  When you want a build Pipeline to test your elements you need three things:
   - Pipeline Module
   - List of elements
   - Links between those elements

  When creating pipelines for tests the only essential part is the list of
   elements. In most cases during the tests, elements are linked in a way that
  `:output` pad is linked to `:input` pad of subsequent element. So we only need
   to pass a list of elements and links can be generated automatically.

  To start a testing pipeline you need to build
  `Membrane.Testing.Pipeline.Options` struct and pass to
  `Membrane.Testing.Pipeline.start_link/2`. Links are generated by
  `populate_links/1`.

  ```
  options = %Membrane.Testing.Pipeline.Options {
    elements: [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ...
    ]
  }
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```

  If you need to pass custom links, you can always do it using `:links` field of
  `Membrane.Testing.Pipeline.Options` struct.

  ```
  options = %Membrane.Testing.Pipeline.Options {
    elements: [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ],
      links: %{
        {:el1, :output} => {:el2, :input}
      }
    }
    ```

  You can also pass a custom pipeline module, by using `:module` field of
  `Membrane.Testing.Pipeline.Options` struct. Every callback of the module
  will be executed before the callbacks of Testing.Pipeline.
  Passed module has to return a proper spec. There should be no elements
  nor links specified in options passed to test pipeline as that would
  result in a failure.

  ```
  options = %Membrane.Testing.Pipeline.Options {
      module: Your.Module
    }
    ```

  See `Membrane.Testing.Pipeline.Options` for available options.

  ## Assertions

  This pipeline is designed to work with `Membrane.Testing.Assertions`. Check
  them out or see example below for more details.

  ## Messaging children

  You can send messages to children using their names specified in the elements
  list. Please check `message_child/3` for more details.

  ## Example usage

  Firstly, we can start the pipeline providing its options:

      options = %Membrane.Testing.Pipeline.Options {
        elements: [
          source: %Membrane.Testing.Source{},
          tested_element: TestedElement,
          sink: %Membrane.Testing.Sink{}
        ]
      }
      {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)


  We can now wait till the end of the stream reaches the sink element (don't forget
  to import `Membrane.Testing.Assertions`):

      assert_end_of_stream(pipeline, :sink)

  We can also assert that the `Membrane.Testing.Sink` processed a specific
  buffer:

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: 1})

  """

  use Membrane.Pipeline

  alias Membrane.{Element, Pipeline}
  alias Membrane.Pipeline.Spec

  defmodule Options do
    @moduledoc """
    Structure representing `options` passed to testing pipeline.

    ##  Test Process
    `pid` of process that shall receive messages when Pipeline invokes playback
    state change callback and receives notification.

    ## Elements
    List of element specs.

    ## Links
    Map describing links between elements.

    ## Module
    Pipeline Module with custom callbacks.

    ## Custom Args
    Arguments for Module's `handle_init` callback.

    If links are not present or set to nil they will be populated automatically
    based on elements order using default pad names.
    """

    defstruct [:elements, :links, :test_process, :module, :custom_args]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            elements: Spec.children_spec_t() | nil,
            links: Spec.links_spec_t() | nil,
            module: module() | nil,
            custom_args: Pipeline.pipeline_options_t() | nil
          }
  end

  defmodule State do
    @moduledoc """
    Structure representing `state`.

    ##  Test Process
    `pid` of process that shall receive messages when Pipeline invokes playback
    state change callback and receives notification.

    ## Module
    Pipeline Module with custom callbacks.

    ## Custom Pipeline State
    State of the pipeline defined by Module.
    """

    @enforce_keys [:test_process, :module]
    defstruct @enforce_keys ++ [:custom_pipeline_state]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            module: module() | nil,
            custom_pipeline_state: any
          }
  end

  def start_link(pipeline_options, process_options \\ []) do
    Pipeline.start_link(__MODULE__, default_options(pipeline_options), process_options)
  end

  def start(pipeline_options, process_options \\ []) do
    Pipeline.start(__MODULE__, default_options(pipeline_options), process_options)
  end

  @doc """
  Links subsequent elements using default pads (linking `:input` to `:output` of
  previous element).

  ## Example

      iex> Pipeline.populate_links([el1: MembraneElement1, el2: MembraneElement2])
      %{{:el1, :output} => {:el2, :input}}
  """
  @spec populate_links(elements :: Spec.children_spec_t()) :: Spec.links_spec_t()
  def populate_links(elements) do
    elements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{output_name, _}, {input_name, _}] ->
      {{output_name, :output}, {input_name, :input}}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Sends message to a child by Element name.

  ## Example

  Knowing that `pipeline` has child named `sink`, message can be sent as follows:

      message_child(pipeline, :sink, {:message, "to handle"})
  """
  @spec message_child(pid(), Element.name_t(), any()) :: :ok
  def message_child(pipeline, child, message) do
    send(pipeline, {:for_element, child, message})
    :ok
  end

  @impl true
  def handle_init(%Options{links: nil, module: nil} = options) do
    new_links = populate_links(options.elements)
    handle_init(%Options{options | links: new_links})
  end

  def handle_init(%Options{module: nil} = options) do
    spec = %Membrane.Pipeline.Spec{
      children: options.elements,
      links: options.links
    }

    new_state = %State{test_process: options.test_process, module: nil}
    {{:ok, spec: spec}, new_state}
  end

  def handle_init(%Options{links: nil, elements: nil} = options) do
    new_state = %State{
      test_process: options.test_process,
      module: options.module,
      custom_pipeline_state: options.custom_args
    }

    eval(:handle_init, [], fn -> {:ok, new_state} end, new_state)
  end

  @impl true
  def handle_stopped_to_prepared(%State{} = state),
    do:
      eval(
        :handle_stopped_to_prepared,
        [],
        fn -> notify_playback_state_changed(:stopped, :prepared, state) end,
        state
      )

  @impl true
  def handle_prepared_to_playing(%State{} = state),
    do:
      eval(
        :handle_prepared_to_playing,
        [],
        fn -> notify_playback_state_changed(:prepared, :playing, state) end,
        state
      )

  @impl true
  def handle_playing_to_prepared(%State{} = state),
    do:
      eval(
        :handle_playing_to_prepared,
        [],
        fn -> notify_playback_state_changed(:playing, :prepared, state) end,
        state
      )

  @impl true
  def handle_prepared_to_stopped(%State{} = state),
    do:
      eval(
        :handle_prepared_to_stopped,
        [],
        fn -> notify_playback_state_changed(:prepared, :stopped, state) end,
        state
      )

  @impl true
  def handle_notification(notification, from, %State{} = state),
    do:
      eval(
        :handle_notification,
        [notification, from],
        fn -> notify_test_process({:handle_notification, {notification, from}}, state) end,
        state
      )

  @impl true
  def handle_spec_started(elements, %State{} = state),
    do:
      eval(
        :handle_spec_started,
        [elements],
        fn -> {:ok, state} end,
        state
      )

  @impl true
  def handle_other({:for_element, element, message}, %State{} = state),
    do:
      eval(
        :handle_other,
        [{:for_element, element, message}],
        fn -> {{:ok, forward: {element, message}}, state} end,
        state
      )

  def handle_other(message, %State{} = state),
    do:
      eval(
        :handle_other,
        [message],
        fn -> notify_test_process({:handle_other, message}, state) end,
        state
      )

  defp default_options(%Options{test_process: nil} = options),
    do: %Options{options | test_process: self()}

  defp default_options(default), do: default

  defp eval(custom_function, custom_args, function, state)

  defp eval(_, _, function, %State{module: nil}),
    do: function.()

  defp eval(custom_function, custom_args, function, %State{module: module} = state) do
    with custom_result = {{:ok, _actions}, _state} <-
           apply(module, custom_function, custom_args ++ [state.custom_pipeline_state])
           |> unify_result do
      result = function.()
      combine_results(custom_result, result)
    end
  end

  defp notify_playback_state_changed(previous, current, %State{} = state) do
    notify_test_process({:playback_state_changed, previous, current}, state)
  end

  defp notify_test_process(message, %State{test_process: test_process} = state) do
    send(test_process, {__MODULE__, self(), message})

    {:ok, state}
  end

  defp unify_result({:ok, state}),
    do: {{:ok, []}, state}

  defp unify_result({{_, _}, _} = result),
    do: result

  defp combine_results({custom_actions, custom_state}, {actions, state}) do
    {combine_actions(custom_actions, actions),
     Map.put(state, :custom_pipeline_state, custom_state)}
  end

  defp combine_actions(l, r) do
    case {l, r} do
      {l, :ok} -> l
      {{:ok, actions_l}, {:ok, actions_r}} -> {:ok, actions_l ++ actions_r}
      {_l, r} -> r
    end
  end
end
