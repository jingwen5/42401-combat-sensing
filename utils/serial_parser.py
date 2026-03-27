# serial_parser.py
# Serial line parser for CSV-style output.

from typing import Optional, Tuple

def parse_csv(line: str, expected_values: int) -> Optional[Tuple[float, ...]]:
    """
    Parse a CSV line and return exactly expected_values floats.
    Returns None if invalid.
    """
    line = line.strip()
    if not line:
        return None

    parts = [p for p in line.split(",") if p != ""]
    if len(parts) < expected_values:
        return None

    try:
        values = tuple(float(parts[i]) for i in range(expected_values))
        return values
    except ValueError:
        return None