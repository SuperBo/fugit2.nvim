-- Ports Pendulum datediff algo to lua
-- Refer to https://github.com/sdispater/pendulum/blob/master/src/pendulum/_helpers.py

local Matrix = require "fugit2.core.matrix"

-- =============
-- | Constants |
-- =============

local MONTHS_ABBR = {
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
}

local MONTHS = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
}

-- ================
-- | Precise Diff |
-- ================

---@class PreciseDiff
---@field years integer
---@field months integer
---@field days integer
---@field hours integer
---@field minutes integer
---@field seconds integer
---@field total_days integer
local Diff = {}
Diff.__index = Diff

---@param years integer
---@param months integer
---@param days integer
---@param hours integer
---@param minutes integer
---@param seconds integer
---@param total_days integer
---@return PreciseDiff
function Diff.new(years, months, days, hours, minutes, seconds, total_days)
  local diff = {
    years = years,
    months = months,
    days = days,
    hours = hours,
    minutes = minutes,
    seconds = seconds,
    total_days = total_days,
  } --[[@as PreciseDiff]]
  setmetatable(diff, Diff)
  return diff
end

-- Gives the duration of the Interval in days.
---@return integer
function Diff:in_days()
  return self.total_days
end

-- Gives the duration of the Interval in weeks.
---@return integer
function Diff:in_weeks()
  local days = self.total_days
  local sign = days < 0 and -1 or 1
  return sign * math.floor(math.abs(days) / 7)
end

-- Gives the duration of the Interval in full years.
---@return integer
function Diff:in_years()
  return self.years
end

-- Gives the duration of the Interval in full months.
---@return integer
function Diff:in_months()
  return self.years * 12 + self.months
end

-- Format ago string
---@param n integer
---@param unit string
local function format_ago(n, unit)
  if n == 1 then
    if unit == "year" then
      return "last year"
    elseif unit == "month" then
      return "last month"
    elseif unit == "day" then
      return "yesterday"
    elseif unit == "week" then
      return "last week"
    end
  end

  return string.format("%d %s%s ago", n, unit, n > 1 and "s" or "")
end

-- Print time in ago format
---@return string
function Diff:ago()
  if self.years > 0 then
    return format_ago(self.years, "year")
  end

  if self.months > 0 then
    return format_ago(self.months, "month")
  end

  local total_days = math.abs(self.total_days)

  if total_days >= 7 then
    local weeks = self:in_weeks()
    return format_ago(weeks, "week")
  end

  if total_days > 0 then
    return format_ago(total_days, "day")
  end

  if self.hours > 0 then
    return format_ago(self.hours, "hour")
  end

  if self.minutes > 0 then
    return format_ago(self.minutes, "minute")
  end

  return format_ago(self.seconds, "second")
end

-- ===============
-- | Main module |
-- ===============

local M = {}

function M.init()
  -- Days in month
  if not M.DAYS_PER_MONTHS then
    local mat = Matrix.new_int8(2, 12) -- use 2 * 16 for better aligned
    local matrix = mat.matrix
    for i = 0, 1 do
      local idx = i * 12
      for m = 1, 12 do -- loop through months
        local m_idx = idx + m - 1
        if m == 2 then
          if i == 0 then -- normal year
            matrix[m_idx] = 28
          else
            matrix[m_idx] = 29 -- leap year
          end
        elseif m < 8 then
          matrix[m_idx] = 30 + (m % 2)
        else
          matrix[m_idx] = 31 - (m % 2)
        end
      end
    end

    M.DAYS_PER_MONTHS = mat
  end
end

-- New datetime helper function
---@param year integer
---@param month integer
---@param day integer
---@param hour integer?
---@param minute integer?
---@param second integer?
---@return osdateparam
function M.datetime(year, month, day, hour, minute, second)
  return {
    year = year,
    month = month,
    day = day,
    hour = math.min(hour or 0, 60),
    min = math.min(minute or 0, 60),
    sec = math.min(second or 0, 60),
  }
end

-- Formats datetime to string, use ISO format by default.
---@param date osdateparam|osdate
---@param use_abbr boolean? use abbreviated month format
---@return string
function M.datetime_tostring(date, use_abbr)
  if use_abbr then
    local m = MONTHS_ABBR[date.month]
    return string.format("%s %d, %d", m, date.day, date.year)
  end

  return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

-- Checks leaf year
---@param year integer
---@return boolean
function M.is_leap_year(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

-- Checks long year
---@param year integer
function M.is_long_year(year)
  local function p(y)
    return y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400)
  end

  return p(year) % 7 == 4 or p(year - 1) % 7 == 3
end

-- Get day number since BC
---@param year integer
---@param month integer
---@param day integer
---@return integer
function M.day_number(year, month, day)
  month = (month + 9) % 12
  year = year - math.floor(month / 10)

  return (
    365 * year
    + math.floor(year / 4)
    - math.floor(year / 100)
    + math.floor(year / 400)
    + math.floor((month * 306 + 5) / 10)
    + day
    - 1
  )
end

-- Check whether two dates are equal.
---@param d1 osdateparam
---@param d2 osdateparam
---@return boolean
function M.date_equal(d1, d2)
  return d1.sec == d1.sec
    and d1.min == d2.min
    and d1.hour == d2.hour
    and d1.day == d2.day
    and d1.month == d2.month
    and d1.year == d2.year
end

-- Calculates a precise difference between two datetimes (d1 - d2).
---@param end_date osdateparam
---@param start_date osdateparam
---@return PreciseDiff date_diff
function M.precise_diff(end_date, start_date)
  local sign = 1

  local d1, d2 = start_date, end_date
  local d1_ts = os.time(d1)
  local d2_ts = os.time(d2)

  if d1_ts == d2_ts then
    return Diff.new(0, 0, 0, 0, 0, 0, 0)
  end

  if d1_ts > d2_ts then
    d1, d2 = d2, d1
    sign = -1
  end

  local d_diff = 0
  local hour_diff = 0
  local min_diff = 0
  local sec_diff = 0
  local total_days = M.day_number(d2.year, d2.month, d2.day) - M.day_number(d1.year, d1.month, d1.day)

  hour_diff = d2.hour - d1.hour
  min_diff = d2.min - d1.min
  sec_diff = d2.sec - d1.sec

  if sec_diff < 0 then
    sec_diff = sec_diff + 60
    min_diff = min_diff - 1
  end

  if min_diff < 0 then
    min_diff = min_diff + 60
    hour_diff = hour_diff - 1
  end

  if hour_diff < 0 then
    hour_diff = hour_diff + 24
    d_diff = d_diff - 1
  end

  local y_diff = d2.year - d1.year
  local m_diff = d2.month - d1.month
  d_diff = d_diff + d2.day - d1.day

  -- handle negative d_diff
  if d_diff < 0 then
    local year = d2.year --[[@as integer]]
    local month = d2.month

    local leap_idx = M.is_leap_year(year) and 1 or 0
    local days_in_month = M.DAYS_PER_MONTHS:at(leap_idx, month - 1)

    if month == 1 then
      month = 12
      year = year - 1
    else
      month = month - 1
    end

    leap_idx = M.is_leap_year(year) and 1 or 0
    local days_in_last_month = M.DAYS_PER_MONTHS:at(leap_idx, month - 1)

    if d_diff < days_in_month - days_in_last_month then
      -- We don't have a full month, we calculate days
      if days_in_last_month < d1.day then
        d_diff = d_diff + d1.day
      else
        d_diff = d_diff + days_in_last_month
      end
    elseif d_diff == days_in_month - days_in_last_month then
      -- We have exactly a full month
      -- We remove the days difference and add one to the months difference
      d_diff = 0
      m_diff = m_diff + 1
    else
      -- We have a full month
      d_diff = d_diff + days_in_last_month
    end

    m_diff = m_diff - 1
  end

  -- handle negative m_diff
  if m_diff < 0 then
    m_diff = m_diff + 12
    y_diff = y_diff - 1
  end

  return Diff.new(
    sign * y_diff,
    sign * m_diff,
    sign * d_diff,
    sign * hour_diff,
    sign * min_diff,
    sign * sec_diff,
    sign * total_days
  )
end

return M
