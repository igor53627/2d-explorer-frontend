defmodule FrontendExWeb.BridgeIntentStatus do
  @moduledoc """
  Display helpers for `GET /api/v2/bridge/intents/:intent_id` (TASK-50).
  """

  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  @doc false
  def valid_intent_id?(id) when is_binary(id), do: Regex.match?(@uuid_re, String.trim(id))
  def valid_intent_id?(_), do: false

  @doc "Map API JSON to template assigns, or `nil` when the payload is unusable."
  @spec build(map() | nil) :: map() | nil
  def build(nil), do: nil

  def build(%{"intent_id" => _, "state" => state} = json) when is_binary(state) do
    bump_count =
      case json["bump_count"] do
        n when is_integer(n) and n >= 0 -> n
        s when is_binary(s) -> parse_bump_count(s)
        _ -> 0
      end

    last_error =
      case json["last_error"] do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end

    claim_status =
      case json["claim_status"] do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end

    state_updated_at =
      case json["state_updated_at"] do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end

    %{
      intent_id: as_string(json["intent_id"]),
      state: state,
      state_label: state_label(state),
      badge_class: badge_class(state),
      bump_count: bump_count,
      claim_status: claim_status,
      last_error: last_error,
      state_updated_at: state_updated_at
    }
  end

  def build(_), do: nil

  defp parse_bump_count(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end

  # Coerce to a string without raising on objects/arrays (which `to_string/1`
  # cannot handle); non-stringable values degrade to "".
  defp as_string(v) when is_binary(v), do: v
  defp as_string(v) when is_integer(v), do: Integer.to_string(v)
  defp as_string(_), do: ""

  defp state_label("consumed"), do: "Consumed"
  defp state_label("claim_failed"), do: "Claim failed"
  defp state_label("in_progress"), do: "In progress"
  defp state_label("active"), do: "Active"
  defp state_label(other), do: other

  defp badge_class("consumed"), do: "badge-success"
  defp badge_class("claim_failed"), do: "badge-danger"
  defp badge_class(_), do: "badge-warning"
end
