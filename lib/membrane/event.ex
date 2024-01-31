defmodule Membrane.Event do
  @moduledoc """
  Represents a communication event within the system, capable of flowing both downstream and upstream.

  Events are dispatched using `t:Membrane.Element.Action.event/0` and handled via the
  `c:Membrane.Element.Base.handle_event/4` callback. Each event must conform to the
  `Membrane.EventProtocol` to ensure proper configuration of its behavior.
  """

  alias Membrane.EventProtocol

  @typedoc """
  Defines the type of a Membrane event, based on the `Membrane.EventProtocol`.
  """
  @type t :: EventProtocol.t()

  @doc """
  Checks if the given argument is a Membrane event.

  Returns `true` if `event` implements the `Membrane.EventProtocol`, otherwise `false`.
  """
  @spec event?(t()) :: boolean
  def event?(event) do
    EventProtocol.impl_for(event) != nil
  end

  @doc """
  Determines if an event is sticky.

  Sticky events persist over time, in contrast to non-sticky events.

  Returns `true` if `event` is sticky according to the `EventProtocol`, otherwise `false`.
  """
  defdelegate sticky?(event), to: EventProtocol

  @doc """
  Checks if an event is asynchronous.

  Asynchronous events are processed in a non-blocking manner.

  Returns `true` if `event` is asynchronous as defined by the `EventProtocol`, otherwise `false`.
  """
  defdelegate async?(event), to: EventProtocol
end
