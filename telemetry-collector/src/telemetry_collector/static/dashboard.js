// Renders the dashboard charts from the JSON data block written by index.html.
(function () {
  "use strict";

  // Categorical palette for the per-feature lines.
  const PALETTE = [
    "#2f6fde", "#e8710a", "#1e9e5a", "#c2185b", "#7b4fd6",
    "#00838f", "#b8860b", "#5d6d7e", "#d84315", "#6d8f1f",
  ];

  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  function render() {
    const block = document.getElementById("chart-data");
    if (!block || typeof Chart === "undefined") {
      return;
    }
    const data = JSON.parse(block.textContent);
    const labels = data.days.map((d) => d.slice(5));
    const muted = cssVar("--muted");
    const line = cssVar("--line");
    Chart.defaults.color = muted;
    Chart.defaults.borderColor = line;
    Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;

    new Chart(document.getElementById("chart-active"), {
      type: "bar",
      data: {
        labels: labels,
        datasets: [{
          label: "Health pings",
          data: data.active,
          backgroundColor: data.flagged.map((f) => (f ? cssVar("--warn") : cssVar("--bar"))),
          borderRadius: 2,
        }],
      },
      options: {
        maintainAspectRatio: false,
        animation: false,
        plugins: { legend: { display: false } },
        scales: { y: { beginAtZero: true, ticks: { precision: 0 } } },
      },
    });

    new Chart(document.getElementById("chart-ratios"), {
      type: "line",
      data: {
        labels: labels,
        datasets: data.ratios.map((series, i) => ({
          label: series.name,
          data: series.values,
          borderColor: PALETTE[i % PALETTE.length],
          backgroundColor: PALETTE[i % PALETTE.length],
          pointRadius: 0,
          borderWidth: 1.5,
          spanGaps: false,
          // Segments ending in a day that is still filling in are dashed.
          segment: { borderDash: (ctx) => (data.filling[ctx.p1DataIndex] ? [4, 3] : undefined) },
        })),
      },
      options: {
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 10, boxHeight: 10 } },
          tooltip: {
            callbacks: {
              label: (ctx) => ctx.dataset.label + ": " + (ctx.parsed.y === null ? "–" : Math.round(ctx.parsed.y * 100) + "%"),
            },
          },
        },
        scales: {
          y: { min: 0, max: 1, ticks: { callback: (v) => Math.round(v * 100) + "%" } },
        },
      },
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render);
  } else {
    render();
  }
})();
