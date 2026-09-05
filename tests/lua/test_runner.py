import tempfile
import unittest
from pathlib import Path

from run_tests import LuaChecks


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "src/gamedata/scripts"
        self.scripts.mkdir(parents=True)
        self.messages = []

    def script(self, name, source):
        (self.scripts / (name + ".script")).write_text(source, encoding="utf-8")

    def checks(self):
        return LuaChecks(self.root, self.messages.append)

    def test_executes_cases_in_script_namespaces(self):
        self.script("modxml_fixture", "value = 42")
        self.script("gamma_arena_fixture", "value = 7")
        self.script("gamma_arena_test_fixture", """
value = 1
function run(run_case)
    return run_case("namespace", function()
        assert(value == 1)
        assert(gamma_arena_fixture.value == 7)
        assert(modxml_fixture.value == 42)
    end)
end
""")
        checks = self.checks()
        self.assertTrue(checks.run(["gamma_arena_test_fixture"]))
        self.assertEqual(checks.passed, ["namespace"])

    def test_failed_case_cannot_be_hidden_by_suite_success(self):
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    run_case("broken", function() error("expected failure") end)
    return true
end
""")
        checks = self.checks()
        self.assertFalse(checks.run(["gamma_arena_test_fixture"]))
        self.assertTrue(any("expected failure" in message for message in self.messages))

    def test_false_suite_result_is_a_failure(self):
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    run_case("passing", function() end)
    return false
end
""")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))

    def test_empty_suite_is_a_failure(self):
        self.script("gamma_arena_test_fixture", "function run(run_case) return true end")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))

    def test_missing_suite_is_a_failure(self):
        self.assertFalse(self.checks().run(["gamma_arena_test_absent"]))

    def test_caught_nested_suite_exception_is_a_failure(self):
        self.script("gamma_arena_test_throwing", 'function run(run_case) error("child failure") end')
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    run_case("outer", function() end)
    pcall(gamma_arena_test_throwing.run, run_case)
    return true
end
""")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))

    def test_empty_nested_suite_is_a_failure(self):
        self.script("gamma_arena_test_empty", "function run(run_case) return true end")
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    run_case("outer", function() end)
    gamma_arena_test_empty.run(run_case)
    return true
end
""")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))

    def test_duplicate_case_is_a_failure(self):
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    run_case("duplicate", function() end)
    return run_case("duplicate", function() end)
end
""")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))

    def test_compiles_even_unreferenced_modules(self):
        self.script("gamma_arena_unused", "this is not Lua")
        self.script("gamma_arena_test_fixture", """
function run(run_case) return run_case("passing", function() end) end
""")
        self.assertFalse(self.checks().run(["gamma_arena_test_fixture"]))
        self.assertTrue(any("gamma_arena_unused" in message for message in self.messages))

    def test_failed_module_load_is_not_cached_as_success(self):
        self.script("gamma_arena_broken", 'error("load failed")')
        self.script("gamma_arena_test_fixture", """
function run(run_case)
    return run_case("retry", function()
        for attempt = 1, 2 do
            local loaded = pcall(function() return gamma_arena_broken end)
            assert(not loaded)
        end
    end)
end
""")
        self.assertTrue(self.checks().run(["gamma_arena_test_fixture"]))

    def test_ui_declarations_do_not_emulate_native_operations(self):
        self.script("gamma_arena_test_fixture", """
class "Window" (CUIScriptWnd)
function Window:label() return "test" end
function run(run_case)
    return run_case("ui", function()
        assert(Window.label({}) == "test")
        local created = pcall(function() return Window() end)
        assert(not created)
        assert(system_ini == nil and getFS == nil and alife == nil)
    end)
end
""")
        self.assertTrue(self.checks().run(["gamma_arena_test_fixture"]))


if __name__ == "__main__":
    unittest.main()
