defmodule Membrane.StreamFormat do
  @moduledoc """
  Defines the capabilities of a pad within the Membrane framework.

  Each pad in a multimedia pipeline has specific capabilities, determining the type and format
  of data it can handle. For example, a pad's capabilities might include handling raw audio
  with a specific sample rate or managing encoded audio in a specified format.

  To successfully link two pads together, their capabilities must be compatible.
  """

  @typedoc """
  Represents the type of a pad's capabilities.
  """
  @type t :: struct
end
