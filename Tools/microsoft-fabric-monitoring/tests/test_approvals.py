from datetime import UTC, datetime, timedelta

import pytest

from fabric_sre.approvals import SUPPORTED_ACTIONS, ActionPlan, require_valid_approval

ENABLED = ["capacity.suspend"]


def _plan(expires: datetime, action: str = "capacity.suspend") -> ActionPlan:
    return ActionPlan(
        action=action,
        resource_id=(
            "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso"
            "/providers/Microsoft.Fabric/capacities/contosocapacity"
        ),
        current_state={"state": "Active"},
        target_state={"state": "Paused"},
        impact="New workloads cannot run.",
        rollback="Resume the capacity.",
        expires_at_utc=expires,
    )


def test_matching_unexpired_approval_is_accepted() -> None:
    now = datetime.now(UTC)
    plan = _plan(now + timedelta(minutes=30))
    require_valid_approval(plan, plan.approval_id, allowed_actions=ENABLED, now=now)


def test_mismatched_approval_is_rejected() -> None:
    now = datetime.now(UTC)
    with pytest.raises(PermissionError, match="does not match"):
        require_valid_approval(
            _plan(now + timedelta(minutes=30)), "wrong", allowed_actions=ENABLED, now=now
        )


def test_expired_approval_is_rejected() -> None:
    now = datetime.now(UTC)
    plan = _plan(now - timedelta(seconds=1))
    with pytest.raises(PermissionError, match="expired"):
        require_valid_approval(plan, plan.approval_id, allowed_actions=ENABLED, now=now)


@pytest.mark.parametrize("action", sorted(SUPPORTED_ACTIONS))
def test_actions_are_refused_when_allow_list_is_empty(action: str) -> None:
    now = datetime.now(UTC)
    plan = _plan(now + timedelta(minutes=30), action=action)
    with pytest.raises(PermissionError, match="not enabled"):
        require_valid_approval(plan, plan.approval_id, allowed_actions=[], now=now)


def test_unsupported_action_is_refused_even_if_listed() -> None:
    now = datetime.now(UTC)
    plan = _plan(now + timedelta(minutes=30), action="workspace.delete")
    with pytest.raises(PermissionError, match="not supported"):
        require_valid_approval(
            plan, plan.approval_id, allowed_actions=["workspace.delete"], now=now
        )
