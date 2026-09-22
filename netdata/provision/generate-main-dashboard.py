#!/usr/bin/env python3
"""Generate the 'main' Netdata custom dashboard JSON for local agent provisioning."""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

DASHBOARD_ID = "local-custom-dashboard"
DASHBOARD_NAME = "main"
DASHBOARD_SLUG = "local-custom-dashboard"
# Bump when card layout/units change so provision page can confirm reload.
DASHBOARD_REVISION = 4
CARD_NAMESPACE = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

# Overview-style gauges (matches Netdata System Overview mainheads).
TOP_GAUGES = [
    {
        "title": "Total Disk Reads",
        "context": "system.io",
        "chart_library": "easypiechart",
        "group_by": ["selected"],
        "aggregation_method": "sum",
        "selected_dimensions": ["in"],
        "colors": ["#3366CC", "#66AA00"],
        "value_range": [0, None],
        "desired_units": "KiB/s",
        "post_group_by": ["selected"],
        "left": 0,
    },
    {
        "title": "Total Disk Writes",
        "context": "system.io",
        "chart_library": "easypiechart",
        "group_by": ["selected"],
        "aggregation_method": "sum",
        "selected_dimensions": ["out"],
        "colors": ["#DC3912", "#FE3912"],
        "value_range": [0, None],
        "desired_units": "KiB/s",
        "post_group_by": ["selected"],
        "left": 2,
    },
    {
        "title": "Uptime",
        # charts.d collector reports uptime in days (system.uptime is seconds only).
        "context": "custom.uptime_days",
        "chart_library": "number",
        "group_by": ["selected"],
        "aggregation_method": "min",
        "selected_dimensions": ["days"],
        "colors": ["#3366CC", "#66AA00"],
        "value_range": [0, None],
        "desired_units": "auto",
        "post_group_by": ["selected"],
        "left": 4,
    },
    {
        "title": "Used RAM",
        "context": "system.ram",
        "chart_library": "gauge",
        "group_by": ["selected"],
        "aggregation_method": "sum",
        "selected_dimensions": ["used"],
        "colors": ["#AAAA11", "#EF0AED"],
        # Chart native unit is MiB; 32768 MiB = 32 GiB max on the gauge scale.
        "value_range": [0, 32768],
        "desired_units": "GiBy",
        "post_group_by": ["selected"],
        "left": 6,
    },
    {
        "title": "Total Network Inbound",
        "context": "system.net",
        "chart_library": "easypiechart",
        "group_by": ["selected"],
        "aggregation_method": "sum",
        "selected_dimensions": ["received"],
        "colors": ["#3366CC", "#66AA00"],
        "value_range": [0, None],
        "desired_units": "kilobits/s",
        "post_group_by": ["selected"],
        "left": 8,
    },
    {
        "title": "Total Network Outbound",
        "context": "system.net",
        "chart_library": "easypiechart",
        "group_by": ["selected"],
        "aggregation_method": "sum",
        "selected_dimensions": ["sent"],
        "colors": ["#DC3912", "#FE3912"],
        "value_range": [0, None],
        "desired_units": "kilobits/s",
        "post_group_by": ["selected"],
        "left": 10,
    },
]

# Full charts below the gauge row (system.load omitted).
DETAIL_CHARTS = [
    ("CPU utilization", "system.cpu", 6, 6),
    ("RAM usage", "system.ram", 12, 6),
    ("Disk I/O (system)", "system.io", 18, 6),
    ("Disk I/O (per disk)", "disk.io", 24, 6),
    ("Network interfaces", "system.net", 30, 6),
    ("Disk space", "disk.space", 36, 6),
]

TOP_ROW_HEIGHT = 5
GAUGE_WIDTH = 2


def _base_card(card_id: str, title: str, context: str) -> dict:
    return {
        "id": card_id,
        "type": "chart",
        "title": title,
        "expanded": False,
        "overlays": {},
        "sparkline": False,
        "nodesScope": [],
        "description": None,
        "nodesSortBy": [{"id": "contribution", "desc": True}],
        "showingInfo": False,
        "contextScope": [context],
        "groupByLabel": [],
        "groupingTime": 0,
        "labelsSortBy": [{"id": "contribution", "desc": True}],
        "groupBySortBy": [],
        "nodesExpanded": {},
        "selectedNodes": [],
        "dimensionsSort": "default",
        "expandedHeight": 300,
        "labelsExpanded": {},
        "selectedLabels": [],
        "groupByExpanded": {},
        "instancesSortBy": [{"id": "contribution", "desc": True}],
        "dimensionsSortBy": [{"id": "contribution", "desc": True}],
        "postGroupByLabel": [],
        "selectedInstances": [],
        "selectedNodeLabelsFilter": [],
        "selectedLegendDimensions": [],
    }


def _gauge_card(card_id: str, spec: dict) -> dict:
    card = _base_card(card_id, spec["title"], spec["context"])
    card.update(
        {
            "groupBy": spec["group_by"],
            "postGroupBy": spec.get("post_group_by", ["selected"]),
            "showPostAggregations": spec.get("show_post_aggregations", False),
            "chartLibrary": spec["chart_library"],
            "aggregationMethod": spec["aggregation_method"],
            "postAggregationMethod": spec["aggregation_method"],
            "selectedDimensions": spec["selected_dimensions"],
            "colors": spec["colors"],
            "valueRange": spec["value_range"],
            "desiredUnits": spec.get("desired_units", "auto"),
        }
    )
    return card


def _card_id(title: str) -> str:
    return str(uuid.uuid5(CARD_NAMESPACE, f"main-{title}"))


def _detail_card(card_id: str, title: str, context: str) -> dict:
    card = _base_card(card_id, title, context)
    card.update(
        {
            "chartType": "stacked",
            "desiredUnits": "auto",
            "groupingMethod": "average",
            "groupBy": ["dimension"],
            "postGroupBy": ["selected"],
            "showPostAggregations": False,
            "chartLibrary": "dygraph",
            "aggregationMethod": "avg",
            "selectedDimensions": [],
            "valueRange": [None, None],
            "postAggregationMethod": "avg",
        }
    )
    return card


def _layout_item(
    card_id: str,
    top: float,
    height: float,
    *,
    left: float = 0,
    width: float = 12,
) -> dict:
    return {
        "id": card_id,
        "top": top,
        "left": left,
        "moved": False,
        "width": width,
        "height": height,
        "minWidth": 1,
        "minHeight": 3,
    }


def build_dashboard() -> dict:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    cards: dict = {}
    layout_items: list = []

    for spec in TOP_GAUGES:
        card_id = _card_id(spec["title"])
        cards[card_id] = _gauge_card(card_id, spec)
        layout_items.append(
            _layout_item(
                card_id,
                top=0,
                height=TOP_ROW_HEIGHT,
                left=spec["left"],
                width=GAUGE_WIDTH,
            )
        )

    for title, context, top, height in DETAIL_CHARTS:
        card_id = _card_id(title)
        cards[card_id] = _detail_card(card_id, title, context)
        layout_items.append(_layout_item(card_id, top, height))

    return {
        "id": DASHBOARD_ID,
        "name": DASHBOARD_NAME,
        "slug": DASHBOARD_SLUG,
        "revision": DASHBOARD_REVISION,
        "isOwner": True,
        "version": 2,
        "disabled": False,
        "createdAt": now,
        "updatedAt": now,
        "snapshot": {
            "name": DASHBOARD_NAME,
            "slug": DASHBOARD_SLUG,
            "items": None,
            "uiState": {
                "cards": cards,
                "layout": {"A": layout_items},
                "containers": {"A": {"name": "A"}},
                "containerIds": ["A"],
                "respectNodesScope": True,
            },
        },
    }


def main() -> None:
    dashboard = build_dashboard()
    out = {
        "version": 2,
        "dashboard": dashboard,
        "dashboards": [dashboard],
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
