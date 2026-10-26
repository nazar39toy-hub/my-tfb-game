"""Original regressions retained under baseline/tests. New schema uses native suite."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name("native_check.py")),run_name="__main__")
