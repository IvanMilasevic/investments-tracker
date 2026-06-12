import sys
from pathlib import Path

# Make scripts/ importable without installing as a package
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
