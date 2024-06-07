-- Test color utils modules

local color = require "fugit2.hl.color"

describe("color_utils", function()
  it("converts rgb color string", function()
    local hex = "ff0080"
    local rgba = color.rgba_from_hex(hex)

    assert.is.not_nil(rgba)
    assert.are.equal(1.0, rgba.red)
    assert.are.equal(0.0, rgba.green)
    assert.are.equal(128 / 255, rgba.blue)
    assert.are.equal(1.0, rgba.alpha)
  end)

  it("converts rgba color string", function()
    local hex = "ff3b80a8"
    local rgba = color.rgba_from_hex(hex)

    assert.is.not_nil(rgba)
    assert.are.equal(1.0, rgba.red)
    assert.are.equal(59 / 255, rgba.green)
    assert.are.equal(128 / 255, rgba.blue)
    assert.are.equal(168 / 255, rgba.alpha)
  end)

  it("converts rgb to lab", function()
    local rgb = color.rgba_from_hex "#54a23d"
    local lab = color.rgb_to_lab(rgb)
    local rgb_new = color.lab_to_rgba(lab)

    assert.is.not_nil(lab)
    assert.is.not_nil(rgb_new)
    assert.is.number(lab.l)
    assert.are.near(59.945, lab.l, 0.01)
    assert.is.number(lab.a)
    assert.are.near(-43.34, lab.a, 0.01)
    assert.is.number(lab.b)
    assert.are.near(44.09, lab.b, 0.01)
    assert.are.near(84 / 255, rgb_new.red, 0.0001)
    assert.are.near(162 / 255, rgb_new.green, 0.0001)
    assert.are.near(61 / 255, rgb_new.blue, 0.0001)
  end)

  it("converts rgb to lab and back to rgb", function()
    local hex = "#54a23d"

    local rgb = color.rgba_from_hex(hex)
    local lab = color.rgb_to_lab(rgb)
    local hex_new = color.lab_to_hex(lab)

    assert.is.not_nil(rgb)
    assert.is.not_nil(lab)
    assert.is.not_nil(hex_new)
    assert.are.equal(hex, hex_new)
  end)

  it("darken lab color", function()
    local lab = { l = 75, a = 20.34, b = 72.25 }

    local darker = color.lab_darken(lab, 10)

    assert.is_true(darker.l < lab.l)
    assert.are.equal(lab.a, darker.a)
    assert.are.equal(lab.b, darker.b)
  end)

  it("lighten lab color", function()
    local lab = { l = 75, a = 20.34, b = 72.25 }

    local lighter = color.lab_lighten(lab, 20)

    assert.is_true(lighter.l > lab.l)
    assert.are.equal(lab.a, lighter.a)
    assert.are.equal(lab.b, lighter.b)
  end)

  it("generates color palette", function()
    local base = "#54a23d"

    local palette = color.generate_palette(base, 6, 0.2)

    assert.array(palette).has.no.holes(6)
    assert.are.equal(base, palette[6])
  end)
end)
