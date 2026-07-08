// lightweight-charts renders `time` (UTC seconds) using the viewer's local
// browser/OS timezone by default. All candle/series data in this app is a
// UTC unix timestamp representing an NSE trading session (09:15-15:30 IST),
// so left unconfigured the time axis silently relabels everything in
// whatever zone happens to be running the browser. On a UTC host that shifts
// the session to 03:45-10:00, and because Charts.jsx requests several days
// of history at once, the axis produces a sawtooth "count up to ~10:00 then
// jump back to ~04:30" pattern once per day boundary, with lightweight-charts'
// own auto-inserted full-date tick (also computed in the wrong zone) showing
// up wedged into the middle of a session. Forcing Asia/Kolkata here makes the
// axis read in market time regardless of where the dashboard is viewed from.
import { TickMarkType } from 'lightweight-charts'

const IST_TIME_ZONE = 'Asia/Kolkata'

const timeFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: IST_TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
  hour12: false
})

const dayFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: IST_TIME_ZONE,
  day: '2-digit',
  month: 'short'
})

const monthFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: IST_TIME_ZONE,
  month: 'short'
})

const yearFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: IST_TIME_ZONE,
  year: 'numeric'
})

// `time` is a lightweight-charts `Time` value: a UTCTimestamp (seconds,
// intraday series — what this app always uses) or a BusinessDay object
// ({year, month, day}, daily series). Only the former appears in practice,
// but BusinessDay is handled so this stays correct if a daily series is
// ever added.
function toDate(time) {
  const seconds = typeof time === 'number'
    ? time
    : Date.UTC(time.year, time.month - 1, time.day) / 1000
  return new Date(seconds * 1000)
}

// Crosshair / legend label — always IST, "DD Mon HH:MM".
export function istTimeFormatter(time) {
  const d = toDate(time)
  return `${dayFmt.format(d)} ${timeFmt.format(d)}`
}

// Axis tick formatter — mirrors lightweight-charts' own convention (date at
// day/month/year boundary ticks, HH:MM otherwise) but computed in IST instead
// of the runtime's local zone.
export function istTickMarkFormatter(time, tickMarkType) {
  const d = toDate(time)
  switch (tickMarkType) {
    case TickMarkType.Year:
      return yearFmt.format(d)
    case TickMarkType.Month:
      return monthFmt.format(d)
    case TickMarkType.DayOfMonth:
      return dayFmt.format(d)
    default:
      return timeFmt.format(d)
  }
}
