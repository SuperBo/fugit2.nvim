-- Color lib util
-- Take reference from https://github.com/DNLHC/glance.nvim/blob/master/lua/glance/color.lua
-- Take reference from https://github.com/NeogitOrg/neogit/blob/master/lua/neogit/lib/color.lua
-- CIELAB color space https://en.wikipedia.org/wiki/CIELAB_color_space

local utils = require "fugit2.utils"

---@class Fugit2ColorRGBA
---@field red number Float [0,1]
---@field green number Float [0,1]
---@field blue number Float [0,1]
---@field alpha number Float [0,1]

---@class Fugit2ColorLAB
---@field l number Float [0,360)
---@field a number Float [0,1]
---@field b number Float [0,1]

---@type table<string, number>
local LAB = {
  Kn = 18,

  Xn = 0.950470,
  Yn = 1,
  Zn = 1.088830,

  t0 = 0.137931034,
  t1 = 0.206896552,
  t2 = 0.12841855,
  t3 = 0.008856452,
}

local M = {}

-- Creates a rgba color from a hex number.
---@param hex string|integer
---@return Fugit2ColorRGBA
function M.rgba_from_hex(hex)
  local n = hex
  if type(hex) == "string" then
    local s = hex:lower():match "#?([a-f0-9]+)"
    n = tonumber(s, 16)
  end

  local rgba = n --[[@as integer]]

  if rgba < 0xffffff then
    rgba = bit.bor(bit.lshift(rgba, 8), 0xff)
  end

  return {
    red = bit.rshift(rgba, 24) / 0xff,
    green = bit.band(bit.rshift(rgba, 16), 0xff) / 0xff,
    blue = bit.band(bit.rshift(rgba, 8), 0xff) / 0xff,
    alpha = bit.band(rgba, 0xff) / 0xff,
  }
end

---@param r number Float [0, 1]
local function rgb_xyz(r)
  if r <= 0.04045 then
    return r / 12.92
  end
  return math.pow((r + 0.055) / 1.055, 2.4)
end

---@param t number Float [0, 1]
local function xyz_lab(t)
  if t > LAB.t3 then
    return math.pow(t, 1 / 3)
  end

  return t / LAB.t2 + LAB.t0
end

---@param r number float [0, 1]
---@param g number float [0, 1]
---@param b number float [0, 1]
local function rgb_to_xyz(r, g, b)
  r = rgb_xyz(r)
  g = rgb_xyz(g)
  b = rgb_xyz(b)

  local x = xyz_lab((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / LAB.Xn)
  local y = xyz_lab((0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / LAB.Yn)
  local z = xyz_lab((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / LAB.Zn)

  return x, y, z
end

---@param rgb Fugit2ColorRGBA
---@return Fugit2ColorLAB
function M.rgb_to_lab(rgb)
  local x, y, z = rgb_to_xyz(rgb.red, rgb.green, rgb.blue)
  local l = math.max(116 * y - 16, 0.0)
  local a = 500 * (x - y)
  local b = 200 * (y - z)
  return { l = l, a = a, b = b }
end

local function is_nan(v)
  return type(v) == "number" and v ~= v
end

local function lab_xyz(t)
  return t > LAB.t1 and t * t * t or LAB.t2 * (t - LAB.t0)
end

local function xyz_rgb(r)
  return (r <= 0.00304 and 12.92 * r or 1.055 * math.pow(r, 1 / 2.4) - 0.055)
end

---@param lab Fugit2ColorLAB
---@return number red Float [0, 1]
---@return number green Float [0, 1]
---@return number blue Float [0, 1]
local function lab_to_rgb(lab)
  local x, y, z, r, g, b

  y = (lab.l + 16) / 116
  x = is_nan(lab.a) and y or y + lab.a / 500
  z = is_nan(lab.b) and y or y - lab.b / 200

  y = LAB.Yn * lab_xyz(y)
  x = LAB.Xn * lab_xyz(x)
  z = LAB.Zn * lab_xyz(z)

  r = xyz_rgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
  g = xyz_rgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
  b = xyz_rgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)

  return r, g, b
end

---@param lab Fugit2ColorLAB
---@return Fugit2ColorRGBA
function M.lab_to_rgba(lab)
  local r, g, b = lab_to_rgb(lab)
  return { red = r, green = g, blue = b, alpha = 1.0 }
end

-- Convert lab to rgb hex
---@return string
function M.lab_to_hex(lab)
  local r, g, b = lab_to_rgb(lab)

  local red_255 = math.max(utils.round(r * 0xff), 0)
  local green_255 = math.max(utils.round(g * 0xff), 0)
  local blue_255 = math.max(utils.round(b * 0xff), 0)

  return string.format("#%02x%02x%02x", red_255, green_255, blue_255)
end

-- Makes a lab color darker.
---@param lab Fugit2ColorLAB
---@param amount number darken amount
---@return Fugit2ColorLAB
function M.lab_darken(lab, amount)
  local l = lab.l - (LAB.Kn * amount)
  return { l = l, a = lab.a, b = lab.b }
end

-- Makes a lab color lighter.
---@param lab Fugit2ColorLAB
---@param amount number lighten amount
---@return Fugit2ColorLAB
function M.lab_lighten(lab, amount)
  local l = lab.l + (LAB.Kn * amount)
  return { l = l, a = lab.a, b = lab.b }
end

-- Generates color palette
---@param base string base color hex string.
---@param n integer number of color to generate.
---@param step integer lightness step used to generate colors.
---@return string[] colors
function M.generate_palette(base, n, step)
  if n <= 0 then
    return {}
  end

  local rgb = M.rgba_from_hex(base)
  local lab = M.rgb_to_lab(rgb)

  local palette = utils.list_new(n) --[[@as string[] ]]
  palette[n] = base

  for i = n - 1, 1, -1 do
    lab = M.lab_darken(lab, step)
    local hex = M.lab_to_hex(lab)
    palette[i] = hex
  end

  return palette
end

return M
