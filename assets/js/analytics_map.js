import { MapChart, ScatterChart } from "echarts/charts";
import { GeoComponent, TooltipComponent } from "echarts/components";
import { init, registerMap, use } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";

use([CanvasRenderer, GeoComponent, MapChart, ScatterChart, TooltipComponent]);

const container = document.querySelector("#analytics-world-map");

if (container) {
  const locations = Array.from(
    container.querySelectorAll("template[data-country]"),
    (location) => {
      const { country, label, latitude, longitude, views } = location.dataset;

      if (
        latitude === undefined ||
        latitude === "" ||
        longitude === undefined ||
        longitude === ""
      ) {
        return null;
      }

      return {
        country,
        label,
        latitude: Number(latitude),
        longitude: Number(longitude),
        views: Number(views),
      };
    },
  ).filter(
    (location) =>
      location &&
      Number.isFinite(location.latitude) &&
      Number.isFinite(location.longitude),
  );
  const theme = getComputedStyle(container);
  const token = (name) => theme.getPropertyValue(name).trim();

  fetch("/images/world.json")
    .then((response) => response.json())
    .then((mapData) => {
      registerMap("gesttalt-world", mapData);

      const chart = init(container);

      chart.setOption({
        aria: { enabled: true },
        backgroundColor: "transparent",
        geo: {
          emphasis: {
            itemStyle: {
              areaColor: token("--surface"),
              borderColor: token("--blue"),
            },
          },
          itemStyle: {
            areaColor: token("--muted"),
            borderColor: token("--line"),
            borderWidth: 1,
          },
          map: "gesttalt-world",
          roam: false,
          silent: false,
        },
        series: [
          {
            coordinateSystem: "geo",
            data: locations.map((location) => ({
              name: location.label,
              value: [location.longitude, location.latitude, location.views],
            })),
            itemStyle: {
              borderColor: token("--paper"),
              borderWidth: 2,
              color: token("--blue"),
            },
            name: "Page views",
            symbol: "circle",
            symbolSize: (value) =>
              Math.min(36, Math.max(10, Math.sqrt(value[2]) * 2)),
            type: "scatter",
            z: 2,
          },
        ],
        tooltip: {
          backgroundColor: token("--paper"),
          borderColor: token("--line"),
          borderWidth: 1,
          formatter: (params) => {
            const views = params.value?.[2];
            return views === undefined
              ? params.name
              : `${params.name}<br>${views} page views`;
          },
          textStyle: {
            color: token("--ink"),
            fontFamily: token("--font-heading"),
          },
          trigger: "item",
        },
      });

      new ResizeObserver(() => chart.resize()).observe(container);
    });
}
