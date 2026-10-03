"""Cron expression parser — five-field cron, no external dependencies.

Fields: minute hour day-of-month month day-of-week.
Each field accepts ``*``, single values, ``a-b`` ranges, ``a,b`` lists and
``/step`` (``*/15``, ``1-5/2``, ``5/10`` = ``5-max/10``). Month and weekday
accept English names (``jan``, ``mon``). Weekday 0 and 7 are Sunday.

Day matching follows Vixie cron: when both day-of-month and day-of-week are
restricted (neither starts with ``*``) a day matches if EITHER matches;
otherwise both must match.

Times are wall-clock times in the schedule's timezone: ``local`` (the
process timezone, honouring ``TZ``) or an IANA name such as ``Europe/Madrid``.
``next_fire`` always returns an aware UTC datetime.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import FrozenSet, Optional

# Four years plus a day: enough for a 29 February schedule to fire.
SEARCH_DAYS = 4 * 366

_MONTHS = {n: i for i, n in enumerate(
    "jan feb mar apr may jun jul aug sep oct nov dec".split(), start=1)}
_DAYS = {n: i for i, n in enumerate("sun mon tue wed thu fri sat".split())}

# (name, low, high, names)
_FIELDS = (
    ("minute", 0, 59, {}),
    ("hour", 0, 23, {}),
    ("day-of-month", 1, 31, {}),
    ("month", 1, 12, _MONTHS),
    ("day-of-week", 0, 7, _DAYS),
)


class CronError(ValueError):
    """The expression is not a valid five-field cron."""


@dataclass(frozen=True)
class CronSpec:
    minutes: FrozenSet[int]
    hours: FrozenSet[int]
    days: FrozenSet[int]
    months: FrozenSet[int]
    weekdays: FrozenSet[int]  # 0 = Sunday … 6 = Saturday
    dom_restricted: bool
    dow_restricted: bool

    def matches_day(self, d: date) -> bool:
        if d.month not in self.months:
            return False
        dom_ok = d.day in self.days
        dow_ok = (d.weekday() + 1) % 7 in self.weekdays  # Python Monday=0
        if self.dom_restricted and self.dow_restricted:
            return dom_ok or dow_ok
        return dom_ok and dow_ok


def _value(token: str, name: str, low: int, high: int, names: dict) -> int:
    key = token.lower()
    if key in names:
        return names[key]
    if not token.isdigit():
        raise CronError(f"{name}: '{token}' is not a number")
    v = int(token)
    if not low <= v <= high:
        raise CronError(f"{name}: {v} out of range {low}-{high}")
    return v


def _field(text: str, name: str, low: int, high: int, names: dict) -> FrozenSet[int]:
    values = set()
    for item in text.split(","):
        if not item:
            raise CronError(f"{name}: empty list item in '{text}'")
        base, slash, step_txt = item.partition("/")
        step = 1
        if slash:
            if not step_txt.isdigit() or int(step_txt) == 0:
                raise CronError(f"{name}: invalid step in '{item}'")
            step = int(step_txt)
        if base == "*":
            start, end = low, high
        elif "-" in base:
            a, _, b = base.partition("-")
            start = _value(a, name, low, high, names)
            end = _value(b, name, low, high, names)
            if start > end:
                raise CronError(f"{name}: range '{base}' is reversed")
        else:
            start = _value(base, name, low, high, names)
            end = high if slash else start
        values.update(range(start, end + 1, step))
    return frozenset(values)


def parse(expr: str) -> CronSpec:
    parts = (expr or "").split()
    if len(parts) != 5:
        raise CronError(f"expected 5 fields, got {len(parts)}: '{expr}'")
    sets = [_field(p, *spec) for p, spec in zip(parts, _FIELDS)]
    weekdays = frozenset(v % 7 for v in sets[4])
    return CronSpec(
        minutes=sets[0], hours=sets[1], days=sets[2], months=sets[3],
        weekdays=weekdays,
        dom_restricted=not parts[2].startswith("*"),
        dow_restricted=not parts[4].startswith("*"),
    )


def _to_utc(y: int, mo: int, d: int, h: int, mi: int, tz: str) -> datetime:
    if tz in ("", "local"):
        ts = time.mktime((y, mo, d, h, mi, 0, 0, 0, -1))
        return datetime.fromtimestamp(ts, timezone.utc)
    from zoneinfo import ZoneInfo
    return datetime(y, mo, d, h, mi, tzinfo=ZoneInfo(tz)).astimezone(timezone.utc)


def _local_date(moment: datetime, tz: str) -> date:
    if tz in ("", "local"):
        return moment.astimezone().date()
    from zoneinfo import ZoneInfo
    return moment.astimezone(ZoneInfo(tz)).date()


def next_fire(spec: CronSpec, after: datetime, tz: str = "local") -> Optional[datetime]:
    """First fire time strictly after ``after`` (aware), as UTC; None if none."""
    if after.tzinfo is None:
        raise ValueError("after must be timezone-aware")
    if tz not in ("", "local"):
        from zoneinfo import ZoneInfo
        try:
            ZoneInfo(tz)
        except Exception as exc:
            raise CronError(f"unknown timezone '{tz}'") from exc
    # Start one day early: DST shifts can move a wall-clock time across UTC days.
    day = _local_date(after, tz) - timedelta(days=1)
    hours, minutes = sorted(spec.hours), sorted(spec.minutes)
    for _ in range(SEARCH_DAYS + 2):
        if spec.matches_day(day):
            for h in hours:
                for mi in minutes:
                    when = _to_utc(day.year, day.month, day.day, h, mi, tz)
                    if when > after:
                        return when
        day += timedelta(days=1)
    return None
