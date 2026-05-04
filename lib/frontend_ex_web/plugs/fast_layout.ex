defmodule FrontendExWeb.Plugs.FastLayout do
  @moduledoc false

  import Phoenix.Controller, only: [put_root_layout: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    put_root_layout(conn, html: {FrontendExWeb.FastLayouts, :classic})
  end
end
