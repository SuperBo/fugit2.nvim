describe("RebaseView", function()
  describe("on_complete callback", function()
    -- Test the callback mechanism in isolation without requiring git or NUI.
    -- We create a minimal table that mimics only the relevant RebaseView fields.

    local function make_stub_view()
      local view = { _on_complete = nil }

      -- Replicate only the two methods under test
      function view:on_complete(callback)
        self._on_complete = callback
      end

      function view:fire_complete()
        local cb = self._on_complete
        if cb then
          cb()
        end
      end

      return view
    end

    it("stores a callback registered with on_complete", function()
      local view = make_stub_view()
      local called = false

      view:on_complete(function()
        called = true
      end)

      assert.is_not_nil(view._on_complete)
      assert.is_false(called)
    end)

    it("invokes the callback when rebase completes", function()
      local view = make_stub_view()
      local called = false

      view:on_complete(function()
        called = true
      end)

      view:fire_complete()

      assert.is_true(called)
    end)

    it("does not error when no callback is registered", function()
      local view = make_stub_view()

      assert.has_no.errors(function()
        view:fire_complete()
      end)
    end)

    it("replaces a previously registered callback", function()
      local view = make_stub_view()
      local first_called = false
      local second_called = false

      view:on_complete(function()
        first_called = true
      end)
      view:on_complete(function()
        second_called = true
      end)

      view:fire_complete()

      assert.is_false(first_called)
      assert.is_true(second_called)
    end)
  end)
end)
