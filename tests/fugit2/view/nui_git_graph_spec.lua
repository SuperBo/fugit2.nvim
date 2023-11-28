local git_graph = require "fugit2.view.nui_git_graph"
local context = require "plenary.context_manager"
local CommitNode = git_graph.CommitNode
local draw_topo_commit_nodes = git_graph.draw_topo_commit_nodes


---@param path string
---@return NuiGitGraphCommitNode[]
local function read_graph_file(path)
  local nodes = {}
  local output = {}

  context.with(context.open(path), function(reader)
    -- read graph
    for content in reader:lines() do
      if content == "---" then
        goto read_expected_output
      end
      local s = vim.split(content, " ", { plain = true })
      local id = s[1]
      local node = CommitNode(id, s[2], {})

      if #s > 2 then
        node.parents = vim.list_slice(s, 3)
      end

      table.insert(nodes, node)
    end

    ::read_expected_output::
    for content in reader:lines() do
      table.insert(output, content)
    end
  end)

  return nodes
end


describe("NuiGitGraph.prepare_commit_node_visualisation", function()
  it("prepares linear graph", function()
    local nodes, _ = read_graph_file("tests/resources/graph_linear.txt")

    local out, length = git_graph.prepare_commit_node_visualisation(nodes)

    assert.array(out).has.no.holes()
    assert.equals(#nodes, #out)
    assert.equals(1, length)
    for _, n in ipairs(out) do
      assert.is_not_nil(n.vis)
      assert.equals(1, n.vis.j)
    end
  end)

  it("prepares simple merge graph 1", function()
    local nodes, _ = read_graph_file("tests/resources/graph_merge_1.txt")

    local out, length = git_graph.prepare_commit_node_visualisation(nodes)
    local js = {1, 1, 2, 2, 1, 1, 1}

    assert.array(out).has.no.holes()
    assert.equals(#nodes, #out)
    assert.equals(2, length)
    for i, n in ipairs(out) do
      assert.is_not_nil(n.vis)
      assert.equals(js[i], n.vis.j)
    end
    assert.same({2}, out[2].vis.merge_cols)
    assert.same({2}, out[6].vis.out_cols)
  end)

  it("prepares simple merge graph 2", function()
    local nodes, _ = read_graph_file("tests/resources/graph_merge_2.txt")

    local out, length = git_graph.prepare_commit_node_visualisation(nodes)
    local js = {1, 1, 1, 2, 2, 1, 1}

    assert.array(out).has.no.holes()
    assert.equals(#nodes, #out)
    assert.equals(2, length)
    for i, n in ipairs(out) do
      assert.is_not_nil(n.vis)
      assert.equals(js[i], n.vis.j)
    end
    assert.same({2}, out[2].vis.merge_cols)
    assert.same({2}, out[6].vis.out_cols)
  end)

  it("prepares merge graph continue after merge", function()
    local nodes, _ = read_graph_file("tests/resources/graph_merge_3.txt")

    local out, length = git_graph.prepare_commit_node_visualisation(nodes)
    local js = {1, 2, 1, 1, 2, 2, 1, 1}

    assert.array(out).has.no.holes()
    assert.equals(#nodes, #out)
    assert.equals(2, length)
    for i, n in ipairs(out) do
      assert.is_not_nil(n.vis)
      assert.equals(js[i], n.vis.j)
    end
    assert.same({2}, out[3].vis.merge_cols)
    assert.same({2}, out[7].vis.out_cols)
  end)
end)


---@param lines NuiLine[]
---@return string[]
local function render_graph_lines(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = l:content()
  end
  return out
end


describe("draw_topo_commit_nodes", function()
  it("draw linear graph", function()
    local nodes, output = read_graph_file("tests/resources/graph_linear.txt")
    local lines = render_graph_lines(draw_topo_commit_nodes(nodes))

    assert.equals(#output, #lines)
    for i, s in ipairs(output) do
      assert.equals(s, lines[i])
    end
  end)

  it("draws simple merge graph", function()
    local nodes, output = read_graph_file("tests/resources/graph_merge_1.txt")
    local lines = render_graph_lines(draw_topo_commit_nodes(nodes))

    assert.equals(#output, #lines)
    for i, s in ipairs(output) do
      assert.equals(s, lines[i])
    end
  end)
end)
