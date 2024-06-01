local context = require "plenary.context_manager"

local Graph = require "fugit2.view.components.commit_log_view"
local CommitNode = Graph.CommitNode

local RESOURCE_DIR = "spec/resources/"

---@param path string
---@param read_output boolean Read expected output or not
---@return Fugit2GitGraphCommitNode[]
---@return string[]
local function read_graph_file(path, read_output)
  local nodes = {}
  local output = {}

  context.with(context.open(RESOURCE_DIR .. path), function(reader)
    -- read graph
    for content in reader:lines() do
      if content == "---" then
        goto read_expected_output
      end
      local s = vim.split(content, " ", { plain = true })
      local id = s[1]
      local node = CommitNode(id, s[2], "A", {}, {})

      if #s > 2 then
        node.parents = vim.list_slice(s, 3)
      end

      table.insert(nodes, node)
    end

    ::read_expected_output::
    if read_output then
      for content in reader:lines() do
        table.insert(output, content)
      end
    end
  end)

  return nodes, output
end

describe("prepare_commit_node_visualisation", function()
  it("prepares linear graph", function()
    local nodes, _ = read_graph_file("graph_linear.txt", false)

    local out, length = Graph.prepare_commit_node_visualisation(nodes)

    assert.array(out).has.no.holes(#nodes)
    assert.are.equal(#nodes, #out)
    assert.are.equal(1, length)
    for _, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(1, n.vis.j)
    end
  end)

  it("prepares double linear graph", function()
    local nodes, _ = read_graph_file("graph_double_linear.txt", false)

    local out, width = Graph.prepare_commit_node_visualisation(nodes)
    local js = { 1, 2, 1, 2, 1, 1, 1, 2, 1 }

    assert.array(out).has.no.holes()
    assert.are.equal(9, #out)
    assert.are.equal(2, width)
    for i, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(js[i], n.vis.j)
    end
    assert.is_nil(out[2].vis.merge_cols)
    assert.are.same({ 1 }, out[2].vis.active_cols)
    assert.are.same({ 2 }, out[7].vis.active_cols)
    assert.is_nil(out[9].vis.active_cols)
  end)

  it("prepares simple merge graph 1", function()
    local nodes, _ = read_graph_file("graph_merge_1.txt", false)

    local out, length = Graph.prepare_commit_node_visualisation(nodes)
    local js = { 1, 1, 2, 2, 1, 1, 1 }

    assert.array(out).has.no.holes()
    assert.are.equal(#nodes, #out)
    assert.are.equal(2, length)
    for i, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(js[i], n.vis.j)
    end
    assert.are.same({ 2 }, out[2].vis.merge_cols)
    assert.are.same({ 1 }, out[3].vis.active_cols)
    assert.are.same({ 1 }, out[4].vis.active_cols)
    assert.are.same({ 2 }, out[5].vis.active_cols)
    assert.are.same({ 2 }, out[6].vis.out_cols)
  end)

  it("prepares simple merge graph 2", function()
    local nodes, _ = read_graph_file("graph_merge_2.txt", false)

    local out, length = Graph.prepare_commit_node_visualisation(nodes)
    local js = { 1, 1, 1, 2, 2, 1, 1 }

    assert.array(out).has.no.holes()
    assert.are.equal(#nodes, #out)
    assert.are.equal(2, length)
    for i, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(js[i], n.vis.j)
    end
    assert.are.same({ 2 }, out[2].vis.merge_cols)
    assert.are.same({ 2 }, out[3].vis.active_cols)
    assert.are.same({ 1 }, out[4].vis.active_cols)
    assert.are.same({ 2 }, out[6].vis.out_cols)
  end)

  it("prepares merge graph continue after merge", function()
    local nodes, _ = read_graph_file("graph_merge_3.txt", false)

    local out, length = Graph.prepare_commit_node_visualisation(nodes)
    local js = { 1, 2, 1, 1, 2, 2, 1, 1 }

    assert.array(out).has.no.holes()
    assert.are.equal(#nodes, #out)
    assert.are.equal(2, length)
    for i, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(js[i], n.vis.j)
    end
    assert.are.same({ 1 }, out[2].vis.active_cols)
    assert.are.same({ 2 }, out[3].vis.merge_cols)
    assert.are.same({ 2 }, out[4].vis.active_cols)
    assert.are.same({ 1 }, out[6].vis.active_cols)
    assert.are.same({ 2 }, out[7].vis.out_cols)
  end)

  it("prepares branch out graph", function()
    local nodes, _ = read_graph_file("graph_branch_out.txt", false)

    local out, width = Graph.prepare_commit_node_visualisation(nodes)
    local js = { 1, 2, 2, 3, 1, 1, 3, 1, 1, 2, 1 }

    assert.array(out).has.no.holes(3)
    assert.are.equal(3, width)
    for i, n in ipairs(out) do
      assert.is.not_nil(n.vis)
      assert.are.equal(js[i], n.vis.j)
    end
  end)
end)

describe("draw_graph_line", function()
  it("draws single commit at col 1", function()
    local cols = { "x" }

    local line = Graph.draw_graph_line(cols, 0, nil)

    assert.are.equal("x", line:content())
  end)

  it("draws single commit at col 2", function()
    local cols = { "", "x" }

    local line = Graph.draw_graph_line(cols, 0, nil)

    assert.are.equal("    x", line:content())
  end)

  it("draws single commit with active columns", function()
    local cols = { "|", "x", "|" }

    local line = Graph.draw_graph_line(cols, 0, 2)

    assert.are.equal("|   x   |", line:content())
  end)

  it("draws active columns only", function()
    local cols = { "|", "", "|", "|" }

    local line = Graph.draw_graph_line(cols, 0)

    assert.are.equal("|       |   |", line:content())
  end)

  it("draws with padding", function()
    local cols = { "x", "|" }

    local line = Graph.draw_graph_line(cols, 3, 1)

    assert.are.equal("x   |   ", line:content())
  end)

  it("draws branch out left", function()
    local cols = { "l", "", "c" }

    local line = Graph.draw_graph_line(cols, 0, 3)

    assert.are.equal("l───────c", line:content())
  end)

  it("draws branch out left with outrange active column", function()
    local cols = { "│", "l", "c" }

    local line = Graph.draw_graph_line(cols, 0, 3)

    assert.are.equal("│   l───c", line:content())
  end)

  it("draws branch out left with active column", function()
    local cols = { "l", "│", "c" }

    local line = Graph.draw_graph_line(cols, 3, 3)

    assert.are.equal("l───┆───c", line:content())
  end)

  it("draws branch out right", function()
    local cols = { "", "c", "r" }

    local line = Graph.draw_graph_line(cols, 0, 2)

    assert.are.equal("    c───r", line:content())
  end)

  it("draws branch out right with outrange active columns", function()
    local cols = { "|", "c", "r", "|" }

    local line = Graph.draw_graph_line(cols, 0, 2)

    assert.are.equal("|   c───r   |", line:content())
  end)

  it("draws branch out right with active columns", function()
    local cols = { "|", "c", "|", "|", "r", "r" }

    local line = Graph.draw_graph_line(cols, 0, 2)

    assert.are.equal("|   c───┆───┆───r───r", line:content())
  end)
end)

---@param lines NuiLine[]
---@return string[]
local function render_graph_lines(lines)
  return vim.tbl_map(function(line)
    return line:content()
  end, lines)
end

describe("draw_commit_nodes", function()
  it("draws linear graph", function()
    local width
    local nodes, output = read_graph_file("graph_linear.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws double linear graph", function()
    local width
    local nodes, output = read_graph_file("graph_double_linear.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws simple merge graph 1", function()
    local width
    local nodes, output = read_graph_file("graph_merge_1.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws simple merge graph 2", function()
    local width
    local nodes, output = read_graph_file("graph_merge_2.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws simple merge graph 3", function()
    local width
    local nodes, output = read_graph_file("graph_merge_3.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws branch out graph", function()
    local width
    local nodes, output = read_graph_file("graph_branch_out.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws merge with branch out graph", function()
    local width
    local nodes, output = read_graph_file("graph_merge_branch_out.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws opctopus out graph", function()
    local width
    local nodes, output = read_graph_file("graph_octopus_crossover_left.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws opctopus graph", function()
    local width
    local nodes, output = read_graph_file("graph_octopus.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws opctopus crossover graph", function()
    local width
    local nodes, output = read_graph_file("graph_octopus_crossover.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws merge cross graph", function()
    local width
    local nodes, output = read_graph_file("graph_merge_cross.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws merge cross graph 2", function()
    local width
    local nodes, output = read_graph_file("graph_merge_cross_2.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws merge complex graph", function()
    local width
    local nodes, output = read_graph_file("graph_merge_complex.txt", true)

    nodes, width = Graph.prepare_commit_node_visualisation(nodes)
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.equal(3, width)
    assert.are.same(output, lines)
  end)

  it("draws graph with wider width", function()
    local nodes, output = read_graph_file("graph_width_more_than_needed.txt", true)

    nodes, _ = Graph.prepare_commit_node_visualisation(nodes)
    local width = 3
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)

  it("draws merge graph with wider width", function()
    local nodes, output = read_graph_file("graph_merge_width_more_than_needed.txt", true)

    nodes, _ = Graph.prepare_commit_node_visualisation(nodes)
    local width = 3
    local lines = render_graph_lines(Graph.draw_commit_nodes(nodes, width))

    assert.are.same(output, lines)
  end)
end)
