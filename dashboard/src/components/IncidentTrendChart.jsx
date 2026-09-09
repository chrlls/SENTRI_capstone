import { useMemo } from 'react'
import { Line } from 'react-chartjs-2'
import {
  CategoryScale,
  Chart as ChartJS,
  Legend,
  LinearScale,
  LineElement,
  PointElement,
  Tooltip,
} from 'chart.js'
import { TRIGGER_SOURCE_CONFIG } from '@/lib/adminMockData'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Legend)

const TRIGGER_KEYS = Object.keys(TRIGGER_SOURCE_CONFIG)

/*
 * The admin dashboard is light-only (`.admin-theme`, index.css) and
 * Chart.js paints on a canvas, so it can't read Tailwind tokens — the few
 * chrome colours it needs are the same brand values used in that block.
 */
const AXIS_TEXT = '#5C6E76'
const GRID_LINE = 'rgba(14, 38, 50, 0.08)'
// Dark tooltip card — near-black SENTRI navy with light text.
const TOOLTIP_BG = '#010919'
const TOOLTIP_TITLE = '#FFFFFF'
const TOOLTIP_BODY = 'rgba(255, 255, 255, 0.82)'
const TOOLTIP_BORDER = 'rgba(255, 255, 255, 0.12)'

/**
 * Four independent trend lines, one per trigger source — a multi-line
 * chart, not a stack: the question here is how each source moves over the
 * 30 days relative to the others, which a stack (reading every band off a
 * shifting baseline) hides. Deliberately plain: 2px lines, no fill, points
 * only on hover, one hue in four shades, a faint horizontal grid. An
 * index-mode tooltip and the legend carry series identity so it never
 * rests on colour alone.
 */
export function IncidentTrendChart({ data }) {
  const chartData = useMemo(
    () => ({
      labels: data.map((row) => row.date),
      datasets: TRIGGER_KEYS.map((key) => ({
        label: TRIGGER_SOURCE_CONFIG[key].label,
        data: data.map((row) => row[key]),
        borderColor: TRIGGER_SOURCE_CONFIG[key].color,
        backgroundColor: TRIGGER_SOURCE_CONFIG[key].color,
        borderWidth: 2,
        tension: 0.3,
        // A 1–2 point window (the "Day" preset) has nothing to draw a line
        // with, so show the markers there; longer windows stay line-only.
        pointRadius: data.length <= 2 ? 3 : 0,
        pointHoverRadius: 3,
        pointHoverBorderWidth: 0,
        pointHoverBackgroundColor: TRIGGER_SOURCE_CONFIG[key].color,
      })),
    }),
    [data],
  )

  const options = useMemo(
    () => ({
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: {
          position: 'bottom',
          labels: {
            usePointStyle: true,
            pointStyle: 'circle',
            boxWidth: 6,
            boxHeight: 6,
            padding: 16,
            color: AXIS_TEXT,
            font: { size: 12 },
          },
        },
        tooltip: {
          backgroundColor: TOOLTIP_BG,
          titleColor: TOOLTIP_TITLE,
          bodyColor: TOOLTIP_BODY,
          borderColor: TOOLTIP_BORDER,
          borderWidth: 1,
          padding: 10,
          boxPadding: 4,
          usePointStyle: true,
          callbacks: {
            title: (items) => data[items[0].dataIndex]?.dateFull ?? items[0].label,
          },
        },
      },
      scales: {
        x: {
          border: { display: false },
          grid: { display: false },
          ticks: {
            color: AXIS_TEXT,
            font: { size: 11 },
            maxRotation: 0,
            autoSkip: true,
            maxTicksLimit: 8,
          },
        },
        y: {
          beginAtZero: true,
          border: { display: false },
          grid: { color: GRID_LINE, drawTicks: false },
          ticks: {
            color: AXIS_TEXT,
            font: { size: 11 },
            precision: 0,
            maxTicksLimit: 6,
            padding: 8,
          },
        },
      },
    }),
    [data],
  )

  return (
    <div className="h-56">
      <Line
        data={chartData}
        options={options}
        aria-label="Multi-line chart of daily incident counts over the last 30 days, one line each for Manual SOS, Voice SOS, Movement Anomaly and Keyword Detected."
      />
    </div>
  )
}
