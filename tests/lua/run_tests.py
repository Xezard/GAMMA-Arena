import argparse
import sys
from pathlib import Path


class LuaChecks:
    def __init__(self, root, output=print, verbose=False):
        from lupa.lua51 import LuaRuntime

        self.root = Path(root).resolve()
        self.output = output
        self.verbose = verbose
        self.passed = []
        self.failures = []
        self.case_names = set()
        self.paths = {}
        for directory in ("src/gamedata/scripts", "dev/gamedata/scripts"):
            for path in sorted((self.root / directory).glob("*.script")):
                if path.stem in self.paths:
                    raise ValueError("Duplicate script namespace: " + path.stem)
                self.paths[path.stem] = path
        self.runtime = LuaRuntime(unpack_returned_tuples=True)
        self.runtime.globals().read_module = self.read_module
        self.runtime.globals().case_count = lambda: len(self.case_names)
        self.runtime.globals().finish_suite = self.finish_suite
        self.runtime.globals().fail_suite = self.fail
        self.runtime.execute("""
setmetatable(_G, { __index = function(globals, name)
    local source = read_module(name)
    if source == nil then return nil end
    local namespace = setmetatable({}, { __index = globals })
    rawset(globals, name, namespace)
    local loaded, reason = pcall(function()
        local chunk = assert(loadstring(source, "@" .. name .. ".script"))
        setfenv(chunk, namespace)()
    end)
    if not loaded then
        rawset(globals, name, nil)
        error(reason, 0)
    end
    local run = rawget(namespace, "run")
    if string.sub(name, 1, 17) == "gamma_arena_test_" and type(run) == "function" then
        namespace.run = function(...)
            local before = case_count()
            local called, succeeded = pcall(run, ...)
            if not called then
                fail_suite(name, succeeded)
                error(succeeded, 0)
            end
            return finish_suite(name, before, succeeded)
        end
    end
    return namespace
end })

CUIScriptWnd = {}
function class(name)
    local namespace = getfenv(2)
    return function(base)
        local declaration = {}
        declaration.__index = declaration
        setmetatable(declaration, {
            __index = base,
            __call = function()
                error("Native UI construction is unavailable in offline tests", 0)
            end
        })
        namespace[name] = declaration
        return declaration
    end
end
""")

    def read_module(self, name):
        path = self.paths.get(name)
        return path.read_text(encoding="utf-8-sig") if path else None

    def fail(self, name, reason):
        self.failures.append(name)
        self.output(f"FAIL {name}: {reason}")
        return False

    def compile_scripts(self):
        compile_script = self.runtime.eval(
            'function(source, name) assert(loadstring(source, "@" .. name)) end'
        )
        valid = True
        for name, path in self.paths.items():
            try:
                compile_script(self.read_module(name), str(path))
            except Exception as error:
                self.fail(name, error)
                valid = False
        return valid

    def run_case(self, name, function):
        if not isinstance(name, str) or not name or name in self.case_names:
            return self.fail(str(name), "Test case name is empty or duplicated")
        self.case_names.add(name)
        try:
            function()
        except Exception as error:
            return self.fail(name, error)
        self.passed.append(name)
        if self.verbose:
            self.output("PASS " + name)
        return True

    def run(self, suites):
        if not self.compile_scripts():
            return False
        for suite in suites:
            before = len(self.case_names)
            try:
                namespace = self.runtime.globals()[suite]
                if namespace is None or not callable(namespace.run):
                    self.fail(suite, "Suite or run(run_case) entry point is missing")
                    continue
                succeeded = namespace.run(self.run_case)
                if suite not in self.failures:
                    self.finish_suite(suite, before, succeeded)
            except Exception as error:
                self.fail(suite, error)
        if not self.case_names:
            self.fail("runner", "No test cases executed")
        self.output(f"Lua 5.1: {len(self.passed)} passed, {len(self.failures)} failures")
        return not self.failures

    def finish_suite(self, suite, before, succeeded):
        if len(self.case_names) == before:
            return self.fail(suite, "Suite executed no test cases")
        if succeeded is not True:
            return self.fail(suite, "Suite did not return true")
        return True


def main():
    parser = argparse.ArgumentParser(description="Execute Arena dev tests without the game engine.")
    parser.add_argument("suites", nargs="*", default=["gamma_arena_test_domain"])
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--verbose", action="store_true")
    arguments = parser.parse_args()
    try:
        checks = LuaChecks(arguments.repo_root, verbose=arguments.verbose)
        return 0 if checks.run(arguments.suites) else 1
    except ImportError as error:
        print(
            "Lua test dependency unavailable. Run: python -m pip install -r tests/lua/requirements.txt",
            file=sys.stderr,
        )
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
