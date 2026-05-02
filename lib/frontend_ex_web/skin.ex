defmodule FrontendExWeb.Skin do
  @moduledoc """
  Skin selection for the 2d fork.

  Upstream `frontend-ex` shipped two skins (`classic` and `53627`) and
  used `FF_SKIN` to pick at runtime. The 2d fork supports only the
  classic skin — keeping a second template set doubles the maintenance
  cost on every change, and the 2d explorer is committed to the classic
  visual idiom by product decision (TASK-13.3).

  This module is preserved only as the single source of truth for
  callers that branch on the current skin; all callers now receive a
  constant. Future cleanup can inline `:classic` at call sites and
  delete this module.
  """

  @type t :: :classic

  @spec current() :: t()
  def current, do: :classic
end
