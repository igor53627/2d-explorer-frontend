defmodule FrontendExWeb.BridgeIntentStatusTest do
  use ExUnit.Case, async: true

  alias FrontendExWeb.BridgeIntentStatus

  test "build/1 maps lifecycle fields and badge classes" do
    intent =
      BridgeIntentStatus.build(%{
        "intent_id" => "550e8400-e29b-41d4-a716-446655440000",
        "state" => "claim_failed",
        "claim_status" => "claim_failed",
        "last_error" => "sign",
        "bump_count" => 2,
        "state_updated_at" => "2026-02-09T10:00:00.000Z"
      })

    assert intent.badge_class == "badge-danger"
    assert intent.last_error == "sign"
    assert intent.bump_count == 2
  end

  test "valid_intent_id?/1" do
    assert BridgeIntentStatus.valid_intent_id?("550e8400-e29b-41d4-a716-446655440000")
    refute BridgeIntentStatus.valid_intent_id?("not-a-uuid")
  end

  test "bump_count accepts string-encoded integers (AC#2)" do
    intent =
      BridgeIntentStatus.build(%{
        "intent_id" => "550e8400-e29b-41d4-a716-446655440000",
        "state" => "in_progress",
        "bump_count" => "3"
      })

    assert intent.bump_count == 3
  end

  test "non-string state_updated_at is dropped so the template can't crash on it" do
    intent =
      BridgeIntentStatus.build(%{
        "intent_id" => "550e8400-e29b-41d4-a716-446655440000",
        "state" => "consumed",
        "state_updated_at" => %{"unexpected" => "object"}
      })

    assert intent.state_updated_at == nil
  end
end
