# Charting library for the workout-tracking PWA

Researched 2026-11-11. Scope: a Vite + React + TypeScript + Tailwind PWA, offline-first, single user, used mostly in iPhone Safari as an installed home-screen app. Datasets run from hundreds to a few thousand points on time-based x-axes.

## TL;DR

**Primary pick: Apache ECharts 6.1 (`echarts`) with `echarts-for-react` 3.0.6, imported through `echarts/core` so it tree-shakes.**
It is the only free, permissively licensed candidate that ships every chart this app needs as built-in features: time axis, stacked bars, a calendar coordinate system for a GitHub-style heatmap, `markPoint`/`markLine` for PR annotations, radar, two-finger pinch zoom on touch screens, touch-friendly pointer snapping, and runtime theme switching for dark mode. The cost is size. The subset this app needs measured about **224 kB min+gzip** (Canvas renderer), roughly 2× Chart.js. Lazy-load the charts route and let the service worker cache the chunk once.

**Runner-up: Chart.js 4.6 + `react-chartjs-2` + `chartjs-plugin-zoom` + `chartjs-plugin-annotation` + `chartjs-chart-matrix` + a date adapter.**
About **100 kB min+gzip** for the same feature set (about 71 kB without zoom and annotations). Choose it if bundle size beats convenience. The trade-off is that pinch zoom comes from a plugin built on Hammer.js (last published 2016), and the calendar heatmap has to be laid out by hand on the matrix chart type.

When to choose which:

- **ECharts:** you want every chart need, the heatmap included, covered by one well-maintained library with native mobile gestures, and ~120 kB extra gzip on a lazily loaded route is acceptable.
- **Chart.js:** bundle size is the top priority, you are fine assembling three or four plugins, and you can live with a hand-built calendar heatmap.
- **Not picked, but worth knowing:** Recharts (or shadcn/ui charts, which are Recharts) gives the most "React + Tailwind native" authoring, but it has no pinch zoom and no heatmap or calendar chart. uPlot is tiny (22.5 kB gzip) but covers only lines, areas and bars, with no built-in pan or touch zoom.

Caveat: nothing here was tested on a physical iPhone. Touch claims come from official docs and source code. Prototype the 1RM chart with pinch zoom on the target device before committing (see [Risks](#risks)).

## How the sizes were measured

Bundlephobia reports the whole package, which says little about tree-shaken use. So I installed the current version of each library and bundled a realistic entry file with esbuild 0.28.2 (`--bundle --minify --format=esm`, `NODE_ENV=production`, React/ReactDOM/react-is external), then gzipped it with `gzip -9`. Each entry imports what the app needs: line + bar (stacked) + time axis + tooltip, plus zoom, annotations, heatmap and radar where the library provides them. Vite/Rollup output will differ by a few percent. Bundlephobia whole-package numbers are available for comparison ([bundlephobia API](https://bundlephobia.com/api/size?package=echarts@6.1.0)).

| Entry (what was imported) | min | min+gzip |
|---|---|---|
| ECharts core: line, bar, heatmap, radar, grid, tooltip, dataZoom, markPoint, markLine, legend, calendar, visualMap, dataset, CanvasRenderer | 666.5 kB | **223.6 kB** |
| Same, SVGRenderer instead of Canvas | 673.8 kB | 227.4 kB |
| ECharts core: line, bar, grid, tooltip, dataZoom only | 561.0 kB | 190.9 kB |
| ECharts full `import * as echarts from 'echarts'` | 1114.8 kB | 373.6 kB |
| `echarts-for-react/lib/core` wrapper | 17.5 kB | 6.2 kB |
| Chart.js tree-shaken (line, bar, radar, time scale, tooltip, legend) + date-fns adapter + zoom + annotation + matrix + react-chartjs-2 | 306.0 kB | **100.3 kB** |
| Chart.js tree-shaken (line, bar, time scale, tooltip, legend) + date-fns adapter + react-chartjs-2, no plugins | 217.6 kB | 70.6 kB |
| Recharts (LineChart, BarChart, RadarChart, axes, Tooltip, Brush, ReferenceDot, ResponsiveContainer) | 439.4 kB | 125.3 kB |
| Recharts minimal (LineChart, Line, XAxis, YAxis, Tooltip) | 359.8 kB | 105.8 kB |
| uPlot (whole lib, not tree-shakeable) | 50.8 kB | 22.5 kB |
| Observable Plot (lineY, barY + stackY, cell, tip + pointerX, windowY) | 280.7 kB | 94.1 kB |
| visx (xychart line, bar stack, axis, grid, tooltip, annotation + heatmap) | 179.6 kB | 64.0 kB |
| Nivo (ResponsiveLine + ResponsiveBar + ResponsiveCalendar) | 395.8 kB | 129.3 kB |
| ApexCharts (whole default export) | 952.1 kB | 285.9 kB |
| Highcharts core (default export, no modules) | 274.6 kB | 102.2 kB |
| Victory (chart, line, bar, stack, axis, zoom/voronoi containers, tooltip, scatter) | 313.7 kB | 99.9 kB |
| Lightweight Charts (createChart, LineSeries, HistogramSeries, markers) | 171.9 kB | 56.0 kB |
| Unovis react (XY container, line, stacked bar, axis, tooltip, crosshair) | 172.5 kB | 55.5 kB |
| AG Charts Community, minimal modules (line, bar, time/number/category axes, legend) | 1164.2 kB | 352.0 kB |
| MUI X Charts (LineChart + BarChart; pulls in `@mui/material`, Emotion) | 477.2 kB | 153.5 kB |

Composition notes from esbuild's metafile: in the Chart.js build, `chart.js` itself is ~175 kB min, date-fns ~45 kB and Hammer.js ~20 kB. In ECharts, `echarts` is ~490 kB and `zrender` ~175 kB. In Recharts, the library is ~301 kB, with d3-shape, es-toolkit, d3-scale, decimal.js-light and Redux Toolkit making up most of the rest.

## Comparison table

Versions, dates and licenses come from the npm registry (`https://registry.npmjs.org/<pkg>`, `dist-tags.latest` and `time`). Weekly downloads cover 2026-11-04 to 2026-11-10 (`https://api.npmjs.org/downloads/point/last-week/<pkg>`). Stars, open issue+PR counts and last push come from the GitHub REST API (`https://api.github.com/repos/<owner>/<repo>`) on 2026-11-11. GitHub's `open_issues_count` includes open PRs.

| Library | Latest (date) | License | min+gzip (app subset) | Render | React | TS | Touch tooltip / pinch-pan zoom | Heatmap / calendar | Annotations | Weekly DL | Repo health |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **ECharts** + echarts-for-react | 6.1.0 (2026-05-19); wrapper 3.0.6 (2026-01-21) | Apache-2.0; wrapper MIT | 224 kB + 6 kB | Canvas or SVG | Wrapper (MIT, 2.18M/wk) | Bundled `.d.ts`; `ComposeOption` for tree-shaken option types | Yes / yes, built in (`dataZoom` inside: two-finger zoom on touch) | Yes, heatmap + calendar coordinate system | `markPoint`, `markLine`, `markArea` | 10.5M | 67.7k stars, 1,479 open, pushed 2026-10-13 |
| **Chart.js** + react-chartjs-2 | 4.6.1 (2026-10-22); wrapper 5.3.1 (2025-10-27) | MIT | 100 kB with plugins (71 kB without) | Canvas | Wrapper (5.65M/wk) | Bundled | Yes / via `chartjs-plugin-zoom` 2.2.0 (2024-11-26, Hammer.js) | Matrix chart plugin 3.1.0 (2026-09-12); calendar layout is manual | `chartjs-plugin-annotation` 3.1.0 (2024-10-16) | 16.6M | 67.8k stars, 648 open, pushed 2026-11-09 |
| Recharts | 3.10.1 (2026-07-25) | MIT | 125 kB | SVG | Native components | Bundled | Tooltip yes (touch handlers) / no pinch; `Brush` slider only | No | `ReferenceDot`, `ReferenceLine`, `ReferenceArea` | 64.7M | 27.7k stars, 475 open, pushed 2026-11-10 |
| shadcn/ui chart | copy-paste, Recharts v3 | MIT | = Recharts | SVG | Native | Yes | = Recharts | No | = Recharts | n/a | shadcn/ui 127.9k stars, pushed 2026-11-11 |
| Tremor (`@tremor/react`) | 3.18.7 (2025-01-13) | Apache-2.0 | 222 kB (bundlephobia, whole package) | SVG (Recharts) | Native | Yes | = Recharts | No | Limited | 531k | Repo last pushed 2025-10-10; peer `react ^18.0.0` only |
| uPlot | 1.6.32 (2025-03-14) | MIT | 22.5 kB | Canvas | Third-party `uplot-react` 1.2.4 | Bundled | Cursor yes / pan and touch zoom only through plugin demos | No | Via hooks/plugins | 1.10M | 10.6k stars, 133 open, pushed 2026-11-10 |
| Observable Plot | 0.6.19 (2026-11-05) | ISC | 94 kB | SVG | Manual (`useEffect` + append) | Bundled | Pointer/tip yes / no zoom or pan | `cell` mark (calendar by hand) | Any mark (text, dot, rule) | 1.38M | 5.4k stars, 347 open, pushed 2026-11-05 |
| visx | 4.0.0 (2026-06-11) | MIT | 64 kB | SVG | Native primitives | Bundled | You build it (`@visx/zoom`, tooltip) | `@visx/heatmap` (layout by hand) | `@visx/annotation` | 611k (`@visx/xychart`) | 21.1k stars, 160 open, pushed 2026-06-22 |
| Nivo | 0.99.0 (2025-05-23) | MIT | 129 kB | SVG (+ Canvas variants) | Native | Bundled | Tooltip yes / no zoom found | Yes, `@nivo/calendar` | `@nivo/annotations` | 2.05M (`@nivo/core`) | 14.1k stars, 73 open, pushed 2026-07-21 |
| ApexCharts | 8.8.1 (2026-11-08) | Community license (free under $2M revenue); MIT up to 5.0.0 | 286 kB (default import only) | SVG | `react-apexcharts` 2.2.0 | Bundled | Yes / built-in zoom | Heatmap type yes | Yes | 2.78M | 15.2k stars, 282 open, pushed 2026-11-08 |
| Highcharts | 13.1.1 (2026-09-20) | Proprietary; free only for personal/educational use | 102 kB core (+ modules) | SVG | `@highcharts/react` 5.4.0 | Bundled | Yes / `chart.zooming.pinchType` | Heatmap module | Annotations module | 3.51M | 12.5k stars, 699 open, pushed 2026-11-11 |
| Victory | 38.0.1 (2026-11-08) | MIT | 100 kB | SVG | Native | Bundled | Touch handlers in zoom container; no pinch found | No | Via labels/scatter | 769k | 11.2k stars, 100 open, pushed 2026-11-10 |
| Lightweight Charts | 5.3.0 (2026-11-10) | Apache-2.0 + attribution required | 56 kB | Canvas | Manual | Bundled | Yes / yes | No | Series markers | 1.96M | 17.8k stars, 113 open, pushed 2026-11-11 |
| Unovis | 1.8.1 (2026-11-10) | Apache-2.0 | 55.5 kB | SVG | `@unovis/react` | Bundled | Crosshair/tooltip; brush | Heatmap component exists | Annotations component | 350k (`@unovis/ts`), 16k (`@unovis/react`) | 2.9k stars, 105 open, pushed 2026-11-10 |
| AG Charts Community | 14.3.0 (2026-11-04) | MIT (Community); Enterprise is commercial | 352 kB | Canvas | `ag-charts-react` | Bundled | Zoom is Enterprise-only | Heatmap is Enterprise-only | Annotations page exists | 2.70M | 490 stars, 21 open, pushed 2026-11-11 |
| MUI X Charts | 9.17.0 (2026-10-30) | MIT (Community); zoom/heatmap are Pro | 154 kB (+ MUI peers) | SVG | Native | Bundled | Zoom/pan with pinch is Pro-only | Heatmap is Pro-only | Reference lines | 1.59M | mui-x: 5.9k stars, 1,181 open |

## Per-library notes

### Apache ECharts (primary pick)

- **Version and cadence.** 6.1.0 was published to npm on 2026-05-19 ([registry](https://registry.npmjs.org/echarts)). The official changelog dates it 2026-05-18 and dates 6.0.0 to 2025-07-30 ([changelog](https://echarts.apache.org/en/changelog.html)). 6.1.0 included time-axis fixes ("duplicate ticks when using time axis", "time axis bug when value scale is in millisecond") and several dataZoom fixes ([changelog](https://echarts.apache.org/en/changelog.html#v6-1-0)). There has been no stable release in the six months since, though `6.1.0-rc.2` and `beta` dist-tags exist ([registry](https://registry.npmjs.org/echarts)).
- **License.** Apache-2.0 ([GitHub API](https://api.github.com/repos/apache/echarts)).
- **Tree-shaking.** The handbook recommends importing from `echarts/core`, `echarts/charts` and `echarts/components` and registering a renderer explicitly, and it documents a narrowed `EChartsOption` type for TypeScript ([Import ECharts](https://echarts.apache.org/handbook/en/basics/import/)). `package.json` declares only the registration entry files (`lib/chart/*.js`, `lib/component/*.js`, themes, i18n) as side effects, so unused modules drop out ([registry](https://registry.npmjs.org/echarts)). Measured subset: 223.6 kB gzip (table above).
- **Rendering.** Canvas or SVG, chosen per instance ([Canvas vs. SVG](https://echarts.apache.org/handbook/en/best-practices/canvas-vs-svg)).
- **Touch.** A `dataZoom` of type `inside` pans when you drag inside the grid; on mobile it zooms "when touches and moved with two fingers in coordinates on touch screens" ([option docs](https://echarts.apache.org/en/option.html#dataZoom-inside)). Since 5.4.0, "intelligent pointer snapping" is on by default for mobile and snaps a tap to the nearest element within 44 px (`pointerSize`) ([handbook](https://echarts.apache.org/handbook/en/how-to/interaction/coarse-pointer/)). `useCoarsePointer` is present in the 6.1.0 type definitions (checked in `echarts/types/dist/shared.d.ts`), and the gesture code lives in `zrender/lib/core/GestureMgr.js` (checked in the installed package).
- **Theming and dark mode.** 6.0 introduced dynamic theme switching without disposing the instance, plus dark-mode support that follows the system preference ([ECharts 6 features](https://echarts.apache.org/handbook/en/basics/release-note/v6-feature/)). `setTheme(theme, opts?)` exists on the instance type in 6.1.0 (checked in `echarts.d.ts`). `echarts-for-react` accepts a `theme` prop (string or object) and an `opts` prop (checked in `echarts-for-react/lib/types.d.ts`).
- **Chart types that matter here.** Line, bar, heatmap, radar and the `calendar` component all ship in `lib/chart` and `lib/component` (checked in the installed package). The calendar takes `range` (a year, a month, or a date pair) and `cellSize` ([calendar option docs](https://github.com/apache/echarts-doc/blob/master/en/option/component/calendar.md), retrieved through Context7).
- **React.** `echarts-for-react` 3.0.6 (MIT, 2.18M/wk) declares peers `echarts ^3 || ^4 || ^5 || ^6` and `react >=16` ([registry](https://registry.npmjs.org/echarts-for-react)). Use `echarts-for-react/lib/core` with a pre-registered `echarts/core` to keep tree-shaking ([README](https://github.com/hustcc/echarts-for-react)). The latest GitHub release tag is v3.0.5 (2025-11-06), npm has 3.0.6, and the repo was pushed 2026-11-08 ([GitHub API](https://api.github.com/repos/hustcc/echarts-for-react)).
- **Maintenance.** 67.7k stars and 1,479 open issues+PRs, last push 2026-10-13 ([GitHub API](https://api.github.com/repos/apache/echarts)). The issue count is high but typical for a library of this scope.
- **Performance reference.** uPlot's benchmark shows ECharts 5.4.1 rendering its 166k-point test in 55 ms ([uPlot README](https://github.com/leeoniya/uPlot)). That is irrelevant at this app's data sizes.

### Chart.js (runner-up)

- 4.6.1, 2026-10-22, MIT ([registry](https://registry.npmjs.org/chart.js); [GitHub releases](https://api.github.com/repos/chartjs/Chart.js/releases?per_page=1)). 16.6M weekly downloads, 67.8k stars, pushed 2026-11-09 ([GitHub API](https://api.github.com/repos/chartjs/Chart.js)).
- Tree-shakeable through component registration (`Chart.register(...)`). `sideEffects` lists only the `auto` and UMD entries ([registry](https://registry.npmjs.org/chart.js)).
- Canvas only.
- **The time scale "requires" a date library and an adapter** ([time axis docs](https://www.chartjs.org/docs/latest/axes/cartesian/time.html)). `chartjs-adapter-date-fns` 3.0.0 dates from 2022-12-11 ([registry](https://registry.npmjs.org/chartjs-adapter-date-fns)) and pulls ~45 kB min of date-fns into my build.
- **Zoom/pan.** `chartjs-plugin-zoom` 2.2.0 (2024-11-26) supports `pinch`, `drag` and `wheel` zoom plus panning, with modifier keys and limits ([options docs](https://www.chartjs.org/chartjs-plugin-zoom/latest/guide/options.html)). It depends on `hammerjs` ([registry](https://registry.npmjs.org/chartjs-plugin-zoom)), whose last npm publish was 2.0.8 on 2016-04-22 ([registry](https://registry.npmjs.org/hammerjs)). The plugin's last release is two years old, though its repo was pushed 2026-10-18 ([GitHub API](https://api.github.com/repos/chartjs/chartjs-plugin-zoom)).
- **Annotations.** `chartjs-plugin-annotation` 3.1.0, 2024-10-16 ([registry](https://registry.npmjs.org/chartjs-plugin-annotation)).
- **Heatmap.** `chartjs-chart-matrix` 3.1.0, 2026-09-12 ([registry](https://registry.npmjs.org/chartjs-chart-matrix)). It draws a matrix of cells; computing the week-of-year × weekday positions for a calendar view is left to you.
- **React.** `react-chartjs-2` 5.3.1 (2025-10-27) declares peers `chart.js ^4.1.1` and `react` 16.8–19 ([registry](https://registry.npmjs.org/react-chartjs-2)).
- **Theming.** Global defaults through `Chart.defaults` ([colors docs](https://www.chartjs.org/docs/latest/general/colors.html)). Dark mode means updating defaults or options and calling `chart.update()`; there is no theme object.

### Recharts, shadcn/ui charts and Tremor

- Recharts 3.10.1 (2026-07-25), MIT, with 64.7M weekly downloads, the most of any candidate ([registry](https://registry.npmjs.org/recharts); [downloads](https://api.npmjs.org/downloads/point/last-week/recharts)). Canary 3.11.0 builds are being published (latest GitHub release `v3.11.0-canary.9`, 2026-11-03) ([GitHub API](https://api.github.com/repos/recharts/recharts/releases?per_page=1)).
- The README describes it as "built with React and D3", with "native SVG support" and declarative components ([README](https://github.com/recharts/recharts/blob/main/README.md)).
- **Interaction gaps.** The only zoom/pan primitive is `Brush`, documented as rendering "a scrollbar that allows the user to zoom and pan in the chart along its XAxis" (checked in `recharts/types/cartesian/Brush.d.ts`). I found no pinch handling in the installed source. Touch-move handlers exist in `RechartsWrapper.js`, so tap/drag tooltips work.
- No heatmap or calendar chart. PR markers can use `ReferenceDot` or `ReferenceLine`.
- 3.x depends on Redux Toolkit, Immer, react-redux and reselect ([registry](https://registry.npmjs.org/recharts)), which helps explain why it costs 125 kB gzip.
- **shadcn/ui chart** is a copy-paste component "built using Recharts", now on Recharts v3. Theming uses CSS variables (`var(--chart-1)`) and `ChartTooltip`/`ChartLegend` helpers ([shadcn chart docs](https://ui.shadcn.com/docs/components/chart)). It fits Tailwind styling best but inherits every Recharts gap above.
- **Tremor.** The npm package `@tremor/react` was last published as 3.18.7 on 2025-01-13, and its peer dependency is `react ^18.0.0`, which excludes React 19 ([registry](https://registry.npmjs.org/@tremor/react)). The current repo holds "Tremor Raw" copy-paste components, with its last commit on 2025-10-10 ([GitHub](https://github.com/tremorlabs/tremor)). Dropped: stale, and it adds nothing over shadcn + Recharts.

### uPlot

- 1.6.32 (2025-03-14), MIT ([registry](https://registry.npmjs.org/uplot)). No npm release in about 20 months, but master has commits as recent as 2026-11-10 ("legend & tooltip improvements") ([GitHub](https://github.com/leeoniya/uPlot)).
- "~50 KB min", Canvas 2D, for time series, lines, areas, OHLC and bars ([README](https://github.com/leeoniya/uPlot)). Measured 22.5 kB gzip.
- Explicit non-features: no animations, and "no built-in drag scrolling/panning", which "can be added externally via the plugin/hooks API", with a `zoom-touch` demo as the example ([README](https://github.com/leeoniya/uPlot); [zoom-touch demo](https://leeoniya.github.io/uPlot/demos/zoom-touch.html)).
- React support only through the third-party `uplot-react` 1.2.4 (2025-07-05) ([registry](https://registry.npmjs.org/uplot-react)).
- No heatmap or radar. Use it only if size is everything and you accept building the interactions yourself.

### Observable Plot

- 0.6.19 (2026-11-05), ISC, depends on the full `d3` package ([registry](https://registry.npmjs.org/@observablehq/plot)). Still pre-1.0.
- SVG output. Its pointer transform drives tips and crosshairs from pointer events; there is no zoom or pan ([pointer docs](https://observablehq.com/plot/interactions/pointer)).
- It exports a `window` transform for moving averages and a `cell` mark for heatmaps (both in `src/index.d.ts`, checked in the package). It is excellent for static analytical charts, but it has no React bindings (you append the returned SVG element in an effect) and no touch zoom. Dropped for the primary role.

### visx

- 4.0.0 (2026-06-11), MIT, with peers React 18/19 and `@react-spring/web` ([registry](https://registry.npmjs.org/@visx/xychart)). Last push 2026-06-22 ([GitHub API](https://api.github.com/repos/airbnb/visx)).
- Low-level primitives (`@visx/heatmap`, `@visx/annotation`, `@visx/zoom` 4.0.0 ([registry](https://registry.npmjs.org/@visx/zoom))). Small (64 kB gzip in the test), but you build the gestures, tooltips and calendar layout yourself. Too much assembly for a one-person app.

### Nivo

- 0.99.0 (2025-05-23), MIT ([registry](https://registry.npmjs.org/@nivo/core)). No release in about 18 months, though the repo was pushed 2026-07-21 ([GitHub API](https://api.github.com/repos/plouc/nivo)).
- Ships a ready-made `@nivo/calendar` in SVG and Canvas variants ([nivo calendar](https://nivo.rocks/calendar/)). I found no zoom/pan in `@nivo/line`'s built output. Still pre-1.0 with a slowing release cadence. If another library lacked only the heatmap, `@nivo/calendar` alone (54 kB gzip per [bundlephobia](https://bundlephobia.com/api/size?package=@nivo/calendar@0.99.0)) could fill the gap, but mixing libraries means maintaining two theming systems.

### ApexCharts

- 8.8.1 (2026-11-08). The license changed from MIT (up to 5.0.0, 2025-07-09) to a custom license from 5.1/5.2 onward ([registry version history](https://registry.npmjs.org/apexcharts)). The current Community License is free for "individuals … whose annual revenue … are less than $2 million USD" and excludes "embedding in a product or platform used by other people" (OEM) ([LICENSE.md](https://raw.githubusercontent.com/apexcharts/apexcharts.js/main/LICENSE.md)). A personal app qualifies today, but the project shipped three major versions in under three months (6.0.0 on 2026-07-17, 7.0.0 on 2026-08-25, 8.0.0 on 2026-10-09) ([registry](https://registry.npmjs.org/apexcharts)).
- 286 kB gzip for the default import. Dropped for license churn and size.

### Highcharts

- 13.1.1 (2026-09-20), under a proprietary license; the npm `license` field points to highcharts.com/license ([registry](https://registry.npmjs.org/highcharts)).
- The non-commercial EULA automatically grants a natural person a "Personal Use" license, covering for example "managing a personal hobby project" and "personal websites/webapps without an income stream". It excludes any business, side-hustle or monetized use and forbids redistributing the source ([Highcharts EULA](https://www.highcharts.com/license-eula)). Any other public website needs a paid SaaS License ([Standard License](https://www.highcharts.com/license)).
- Technically strong (pinch zoom via `chart.zooming.pinchType`, plus heatmap and annotations modules, all present in the installed package), but the app would have to stay strictly personal forever. Dropped on licensing.

### Victory

- 38.0.1 (2026-11-08), MIT, active ([registry](https://registry.npmjs.org/victory); [GitHub API](https://api.github.com/repos/FormidableLabs/victory)).
- `VictoryZoomContainer` offers `allowPan`, `allowZoom`, `zoomDimension` and `downsample` ([docs](https://nearform.com/open-source/victory/docs/api/victory-zoom-container)). Its built output has touch-start/move/end handlers but contains no "pinch" code, so one-finger drag-pan probably works and two-finger pinch probably does not. Unverified on a device.
- No heatmap or calendar. It offers nothing over Recharts or ECharts for this app.

### Lightweight Charts (TradingView)

- 5.3.0 (2026-11-10), Apache-2.0, very active ([registry](https://registry.npmjs.org/lightweight-charts); [GitHub](https://github.com/tradingview/lightweight-charts)).
- Built for financial charts. **The license requires the NOTICE attribution plus a link to tradingview.com** in the app; the `attributionLogo` option (default `true`) satisfies it ([README, License section](https://github.com/tradingview/lightweight-charts#license); `attributionLogo` doc comment in `dist/typings.d.ts`).
- No stacked bars, heatmap or radar. Dropped as off-target.

### Unovis

- 1.8.1 (2026-11-10), Apache-2.0, by F5 ([registry](https://registry.npmjs.org/@unovis/ts); [GitHub API](https://api.github.com/repos/f5/unovis)).
- Has stacked-bar, heatmap, annotations, crosshair, brush and tooltip components (component directory checked in the installed package). Only 16k weekly downloads for `@unovis/react` ([downloads](https://api.npmjs.org/downloads/point/last-week/@unovis/react)), and the `@unovis/ts` dependency list includes Leaflet, MapLibre and Three.js ([registry](https://registry.npmjs.org/@unovis/ts)). Tree-shaking kept my build to 55.5 kB gzip, but the small community makes it a riskier bet.

### AG Charts

- 14.3.0 (2026-11-04). Community is MIT; zoom, navigator, crosshairs and the heatmap are Enterprise features ([Community vs. Enterprise](https://www.ag-grid.com/charts/javascript/community-vs-enterprise/)). Community alone came to 352 kB gzip in my build. Dropped.

### MUI X Charts

- 9.17.0 (2026-10-30), MIT Community package ([registry](https://registry.npmjs.org/@mui/x-charts)). Its peers are `@mui/material`, `@mui/system` and Emotion, which a Tailwind app does not otherwise need.
- Zoom and pan, including pinch, are a Pro-plan feature ([zoom docs](https://mui.com/x/react-charts/zoom-and-pan/)), and so is the heatmap ([heatmap docs](https://mui.com/x/react-charts/heatmap/); [licensing](https://mui.com/x/introduction/licensing/)). Dropped.

## Covering each chart need with ECharts

All of these assume one shared `echarts/core` setup that registers `LineChart, BarChart, HeatmapChart, RadarChart`, `GridComponent, TooltipComponent, DataZoomComponent, MarkPointComponent, MarkLineComponent, LegendComponent, CalendarComponent, VisualMapComponent, DatasetComponent` and `CanvasRenderer` (the 223.6 kB gzip set measured above).

| Need | ECharts approach |
|---|---|
| Estimated 1RM / top-set weight over time | `xAxis: { type: 'time' }` with one `line` series per exercise and `[timestamp, value]` data. `tooltip: { trigger: 'axis' }` gives a tap-and-drag crosshair. `dataZoom: [{ type: 'inside' }]` adds drag-pan and two-finger pinch ([dataZoom-inside](https://echarts.apache.org/en/option.html#dataZoom-inside)); set `minValueSpan` (for example 7 days in ms) to stop over-zooming. |
| PR markers / annotations | `markPoint.data` on the series with the PR coordinates, or `markLine` for a horizontal "current PR" line. |
| Weekly volume per muscle group (stacked bars) | One `bar` series per muscle group sharing the same `stack` value, on a category axis of week labels or a time axis with weekly buckets. Aggregate in Dexie queries; ECharts does not bucket data for you. |
| Bodyweight trend + moving average | Two `line` series: raw points (small `symbolSize`) and the average. Compute the 7-day moving average in app code; ECharts has no moving-average option for line series. |
| GitHub-style training heatmap | A `calendar` component with `range: '2026'` (or a date pair) and `cellSize`, plus a `heatmap` series with `coordinateSystem: 'calendar'` and a `visualMap` for the color scale ([calendar docs](https://github.com/apache/echarts-doc/blob/master/en/option/component/calendar.md)). |
| Muscle balance radar | A `radar` component with one indicator per muscle group and a `radar` series. |
| Dark mode | Register light and dark themes built from the Tailwind palette, then call `chart.setTheme(...)` when `prefers-color-scheme` or the app toggle changes (dynamic switching is new in 6.0 ([v6 features](https://echarts.apache.org/handbook/en/basics/release-note/v6-feature/))). I did not verify whether ECharts resolves CSS custom properties, so read Tailwind variables with `getComputedStyle` and pass concrete colors into the theme. |
| Small tap targets on a phone | Pointer snapping is on by default on mobile (44 px radius, tunable with `pointerSize`) ([handbook](https://echarts.apache.org/handbook/en/how-to/interaction/coarse-pointer/)). |
| TypeScript | Build the option type with `ComposeOption<LineSeriesOption \| BarSeriesOption \| …>` as shown in the import guide ([Import ECharts](https://echarts.apache.org/handbook/en/basics/import/)), so options for an unregistered chart or component fail type checking. |
| Bundle / offline | Put all charts behind `React.lazy` on the stats route. Vite emits a separate chunk and the PWA service worker precaches it, so the ~230 kB gzip downloads once. |

## Risks

1. **Size.** ECharts is the heaviest viable option at ~224 kB gzip for this subset, versus ~100 kB for Chart.js with plugins. Mitigation: lazy-load it, import from `echarts/core` only, and never `import 'echarts'`, which costs 374 kB gzip.
2. **Gesture conflicts with page scroll on iOS (unverified).** `dataZoom` inside pans on a one-finger drag by default (`moveOnMouseMove` defaults to `true`) ([dataZoom-inside option source](https://github.com/apache/echarts-doc/blob/master/en/option/component/data-zoom-inside.md)). On a scrolling page this could capture vertical swipes or fight the tap-and-drag tooltip. I could not test this on an iPhone. Prototype first; if it conflicts, set `moveOnMouseMove: false` (pinch still zooms) or use a `slider` dataZoom under the chart.
3. **Release cadence.** ECharts has gone six months without a stable release since 6.1.0 (2026-05-19), though RC and beta tags exist. That gap is normal for this Apache project, but fixes can take a while to ship.
4. **Wrapper drift.** `echarts-for-react` is a separate MIT project with one main maintainer. It is thin (6 kB gzip), so writing your own `useECharts` hook (init on mount, `setOption` on change, `ResizeObserver`, `dispose` on unmount) is a cheap fallback.
5. **Not Tailwind-native.** Styling lives in JS option and theme objects, not classes. A tooltip `formatter` that returns HTML strings must escape user-entered exercise names. The 6.1.0 changelog includes a tooltip XSS fix for the `lines` series ([changelog](https://echarts.apache.org/en/changelog.html#v6-1-0)), a reminder to sanitize any HTML you inject.
6. **Runner-up risks (Chart.js).** The zoom plugin rests on Hammer.js, unmaintained since 2016, and the plugin's last release is from 2024-11-26. The calendar heatmap needs custom date-to-cell layout code.

## What was not verifiable

- Real-device behavior in iPhone Safari (pinch, tap tooltips, scroll conflicts) for every library. All touch statements come from docs and from searching the installed sources.
- Whether ECharts themes accept CSS custom properties directly.
- Exact Vite/Rollup bundle sizes. The numbers come from esbuild 0.28.2 and should land within a few percent.
- Tree-shaken sizes for ApexCharts and Highcharts: I measured only their default imports.
- npm "last week" download counts are a one-week snapshot and vary from week to week.

## Sources

Registry and metrics (queried 2026-11-11):

- npm registry metadata: https://registry.npmjs.org/echarts, https://registry.npmjs.org/echarts-for-react, https://registry.npmjs.org/chart.js, https://registry.npmjs.org/react-chartjs-2, https://registry.npmjs.org/chartjs-plugin-zoom, https://registry.npmjs.org/chartjs-plugin-annotation, https://registry.npmjs.org/chartjs-chart-matrix, https://registry.npmjs.org/chartjs-adapter-date-fns, https://registry.npmjs.org/hammerjs, https://registry.npmjs.org/recharts, https://registry.npmjs.org/@tremor/react, https://registry.npmjs.org/uplot, https://registry.npmjs.org/uplot-react, https://registry.npmjs.org/@observablehq/plot, https://registry.npmjs.org/@visx/xychart, https://registry.npmjs.org/@visx/zoom, https://registry.npmjs.org/@nivo/core, https://registry.npmjs.org/apexcharts, https://registry.npmjs.org/highcharts, https://registry.npmjs.org/@highcharts/react, https://registry.npmjs.org/victory, https://registry.npmjs.org/lightweight-charts, https://registry.npmjs.org/@unovis/ts, https://registry.npmjs.org/@unovis/react, https://registry.npmjs.org/ag-charts-community, https://registry.npmjs.org/@mui/x-charts
- npm weekly downloads: `https://api.npmjs.org/downloads/point/last-week/<package>` for each package above
- GitHub REST API repo stats and latest releases: `https://api.github.com/repos/<owner>/<repo>` and `/releases?per_page=1` for apache/echarts, hustcc/echarts-for-react, chartjs/Chart.js, reactchartjs/react-chartjs-2, chartjs/chartjs-plugin-zoom, recharts/recharts, leeoniya/uPlot, observablehq/plot, airbnb/visx, plouc/nivo, apexcharts/apexcharts.js, highcharts/highcharts, FormidableLabs/victory, tremorlabs/tremor, shadcn-ui/ui, tradingview/lightweight-charts, f5/unovis, ag-grid/ag-charts, mui/mui-x
- Bundlephobia whole-package sizes: `https://bundlephobia.com/api/size?package=<pkg>@<version>`
- My own esbuild measurements of the installed packages (method described above)

Official docs and READMEs:

- ECharts 6 features: https://echarts.apache.org/handbook/en/basics/release-note/v6-feature/
- ECharts changelog: https://echarts.apache.org/en/changelog.html
- ECharts import, tree-shaking and TypeScript: https://echarts.apache.org/handbook/en/basics/import/
- ECharts dataZoom-inside: https://echarts.apache.org/en/option.html#dataZoom-inside
- ECharts pointer snapping: https://echarts.apache.org/handbook/en/how-to/interaction/coarse-pointer/
- ECharts Canvas vs. SVG: https://echarts.apache.org/handbook/en/best-practices/canvas-vs-svg
- ECharts calendar option source: https://github.com/apache/echarts-doc/blob/master/en/option/component/calendar.md
- ECharts dataZoom-inside option source: https://github.com/apache/echarts-doc/blob/master/en/option/component/data-zoom-inside.md
- echarts-for-react README: https://github.com/hustcc/echarts-for-react
- Chart.js time axis: https://www.chartjs.org/docs/latest/axes/cartesian/time.html
- Chart.js colors: https://www.chartjs.org/docs/latest/general/colors.html
- chartjs-plugin-zoom options: https://www.chartjs.org/chartjs-plugin-zoom/latest/guide/options.html
- Recharts README: https://github.com/recharts/recharts/blob/main/README.md
- shadcn/ui chart: https://ui.shadcn.com/docs/components/chart
- Tremor repo: https://github.com/tremorlabs/tremor
- uPlot README: https://github.com/leeoniya/uPlot
- uPlot zoom-touch demo: https://leeoniya.github.io/uPlot/demos/zoom-touch.html
- Observable Plot pointer: https://observablehq.com/plot/interactions/pointer
- Nivo calendar: https://nivo.rocks/calendar/
- ApexCharts license: https://raw.githubusercontent.com/apexcharts/apexcharts.js/main/LICENSE.md
- Highcharts EULA (non-commercial): https://www.highcharts.com/license-eula
- Highcharts Standard License: https://www.highcharts.com/license
- Victory zoom container: https://nearform.com/open-source/victory/docs/api/victory-zoom-container
- Lightweight Charts README: https://github.com/tradingview/lightweight-charts
- AG Charts Community vs. Enterprise: https://www.ag-grid.com/charts/javascript/community-vs-enterprise/
- MUI X licensing: https://mui.com/x/introduction/licensing/
- MUI X zoom and pan: https://mui.com/x/react-charts/zoom-and-pan/
- MUI X heatmap: https://mui.com/x/react-charts/heatmap/
