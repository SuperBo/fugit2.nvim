-- Test pendulum module

local pendulum = require "fugit2.core.pendulum"

pendulum.init()

---@param diff PreciseDiff
---@param years integer?
---@param months integer?
---@param days integer?
---@param hours integer?
---@param minutes integer?
---@param seconds integer?
local function assert_diff(diff, years, months, days, hours, minutes, seconds)
  assert.equals(years or 0, diff.years)
  assert.equals(months or 0, diff.months)
  assert.equals(days or 0, diff.days)
  assert.equals(hours or 0, diff.hours)
  assert.equals(minutes or 0, diff.minutes)
  assert.equals(seconds or 0, diff.seconds)
end

describe("pendulum", function()
  it("detects leap year", function()
    local leap_years = { 1964, 1976, 2024, 2028, 2048, 2280 }
    local non_leap_years = { 1900, 2100, 2200, 2021, 2023, 1987, 2115 }

    for _, year in ipairs(leap_years) do
      assert.is_true(pendulum.is_leap_year(year))
    end

    for _, year in ipairs(non_leap_years) do
      assert.is_false(pendulum.is_leap_year(year))
    end
  end)

  it("inits correct days in month in normal year", function()
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

    for i, num_days in ipairs(days) do
      assert.equals(num_days, pendulum.DAYS_PER_MONTHS:at(0, i - 1))
    end
  end)

  it("inits correct days in month in leap year", function()
    local days = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

    for i, num_days in ipairs(days) do
      assert.equals(num_days, pendulum.DAYS_PER_MONTHS:at(1, i - 1))
    end
  end)

  it("calculates precise diff", function()
    local dt1 = pendulum.datetime(2003, 3, 1, 0, 0, 0)
    local dt2 = pendulum.datetime(2003, 1, 31, 23, 59, 59)

    local diff1 = pendulum.precise_diff(dt1, dt2)
    local diff2 = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff1, 0, 1, 0, 0, 0, 1)
    assert_diff(diff2, 0, -1, 0, 0, 0, -1)
  end)

  it("calculates precise diff 2", function()
    local dt1 = pendulum.datetime(2012, 3, 1, 0, 0, 0)
    local dt2 = pendulum.datetime(2012, 1, 31, 23, 59, 59)

    local diff1 = pendulum.precise_diff(dt1, dt2)
    local diff2 = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff1, 0, 1, 0, 0, 0, 1)
    assert.equals(30, diff1.total_days)
    assert_diff(diff2, 0, -1, 0, 0, 0, -1)
    assert.equals(-30, diff2.total_days)
  end)

  it("calculates precise diff 3", function()
    local dt1 = pendulum.datetime(2001, 1, 1)
    local dt2 = pendulum.datetime(2003, 9, 17, 20, 54, 47)

    local diff = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff, 2, 8, 16, 20, 54, 47)
  end)

  it("calculates precise diff 1 year", function()
    local dt1 = pendulum.datetime(2017, 2, 17, 16, 5, 45)
    local dt2 = pendulum.datetime(2018, 2, 17, 16, 5, 45)

    local diff = pendulum.precise_diff(dt2, dt1)
    assert_diff(diff, 1, 0, 0, 0, 0, 0)
  end)
end)
