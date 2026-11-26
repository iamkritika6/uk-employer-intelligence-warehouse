"""Run the whole warehouse pipeline, in order, from raw files to quality checks.

Why this exists: until the pipeline can be run with one command, the results
are not reproducible, and a number in a README that nobody else can regenerate
is just an assertion.

Design notes
------------
The SQL does the work. This script only decides what runs, in what order, and
reports what happened. Transformation logic lives in .sql files where it can be
read and reviewed, not buried in Python strings. The two exceptions are the
COPY statements, which are generated here because they need the actual
filenames found on disk, and those change every time a publisher issues a new
file.

No third-party packages are required. The script talks to PostgreSQL by
invoking psql inside the Docker container, which is already a dependency of
the project. Using psycopg instead would be reasonable, but it would add an
install step for no behaviour this script needs.

Usage
-----
    py scripts/run_pipeline.py                 # everything
    py scripts/run_pipeline.py --skip-raw      # skip the slow raw reload
    py scripts/run_pipeline.py --only staging  # one layer
    py scripts/run_pipeline.py --dry-run       # show the plan, run nothing
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SQL_ROOT = PROJECT_ROOT / "sql"
RAW_DIR = PROJECT_ROOT / "data" / "raw"
CONTAINER = "uk_employer_intel_pg"

# Where the raw folder is mounted inside the container (see docker-compose.yml)
CONTAINER_RAW_DIR = "/data/raw"

# Layers run in this order. The numeric prefixes on the folders are what makes
# the order explicit on disk rather than hidden in this list.
LAYERS = [
    ("setup", "00_raw", ["00_setup.sql"]),
    ("raw-ddl", "00_raw", ["01_raw_licensed_employers.sql", "02_raw_companies.sql"]),
    ("staging", "10_staging", None),
    # Matching runs BEFORE marts, despite the folder numbering. dim_company is
    # built from the companies that matching linked, so the match table has to
    # exist first. The folders are numbered by layer, not by execution order,
    # and this list is the authority on order.
    ("matching", "30_matching", None),
    ("marts", "20_marts", None),
    # The sector definition is a table and a view that the analysis queries
    # and the figures depend on. It lives in 50_analysis because that is what
    # it belongs to, but it has to be CREATED by the pipeline: the view reads
    # dim_company, so the CASCADE when marts rebuilds that table drops the
    # view with it. Leaving it out meant a full rebuild silently removed it,
    # and the next thing to use it failed with "relation does not exist".
    # Only the definition file runs here; the queries themselves are run by
    # hand, since their output is for reading, not for loading.
    ("analysis-defs", "50_analysis", ["00_technology_sic_definition.sql"]),
    ("snapshots", "40_snapshots", None),
    ("quality", "60_quality", None),
]


def read_env() -> dict[str, str]:
    """Read .env. Falls back to .env.example so --dry-run works on a fresh clone."""
    env_path = PROJECT_ROOT / ".env"
    if not env_path.exists():
        env_path = PROJECT_ROOT / ".env.example"
        print(f"  note: no .env found, reading {env_path.name}")
    values: dict[str, str] = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def psql(env: dict[str, str], sql: str | None = None, sql_file: Path | None = None) -> str:
    """Run SQL in the container. ON_ERROR_STOP makes psql exit non-zero on the
    first error, so a broken step stops the pipeline instead of letting later
    steps run against half-built tables."""
    command = [
        "docker", "exec", "-i", CONTAINER,
        "psql", "-U", env["POSTGRES_USER"], "-d", env["POSTGRES_DB"],
        "-v", "ON_ERROR_STOP=1", "-P", "pager=off",
    ]
    payload = sql if sql is not None else sql_file.read_text(encoding="utf-8")
    result = subprocess.run(
        command, input=payload, capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"psql failed (exit {result.returncode})\n{result.stderr.strip()}"
        )
    return result.stdout


def find_raw_files() -> dict[str, list[Path]]:
    """Locate the downloaded files by pattern, not by hard-coded name.

    Publishers change the date in the filename on every release, so matching on
    a pattern means a new download works without editing code. Register files
    are returned sorted, so multiple snapshots load oldest first.
    """
    register = sorted(RAW_DIR.glob("SP_*Worker*Register*.csv"))
    companies = sorted(RAW_DIR.glob("BasicCompanyData*.csv"))
    return {"register": register, "companies": companies}


def snapshot_date_from(filename: str) -> str | None:
    """The publisher puts the publication date in the filename."""
    match = re.search(r"(\d{4}-\d{2}-\d{2})", filename)
    return match.group(1) if match else None


def load_register(env: dict[str, str], path: Path) -> None:
    name = path.name
    sql = f"""
        BEGIN;
        DELETE FROM raw.licensed_employers WHERE source_file = '{name}';
        COPY raw.licensed_employers
            (organisation_name, town_city, county, type_and_rating, route)
        FROM '{CONTAINER_RAW_DIR}/{name}' WITH (FORMAT csv, HEADER true);
        UPDATE raw.licensed_employers SET source_file = '{name}'
        WHERE source_file IS NULL;
        COMMIT;
    """
    psql(env, sql=sql)


def load_companies(env: dict[str, str], path: Path) -> None:
    """Load the Companies House file.

    The file contains a blank line (line 3,010,663 in the 2026-11-01 release),
    which COPY rejects with "missing data for column". Rather than editing the
    publisher's file, it is read through grep, which drops blank lines in
    transit. The downloaded file stays byte-for-byte as published.

    This filter would also remove a blank line inside a quoted field, which
    would corrupt that record. The quality checks reconcile the row count
    afterwards, which is what makes the shortcut safe to rely on.
    """
    name = path.name
    columns = psql(env, sql="""
        SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
        FROM information_schema.columns
        WHERE table_schema = 'raw' AND table_name = 'companies'
          AND column_name NOT IN ('source_file', 'loaded_at');
    """)
    column_list = columns.strip().splitlines()[2].strip()
    sql = f"""
        BEGIN;
        DELETE FROM raw.companies WHERE source_file = '{name}';
        COPY raw.companies ({column_list})
        FROM PROGRAM 'grep -v "^[[:space:]]*$" {CONTAINER_RAW_DIR}/{name}'
        WITH (FORMAT csv, HEADER true);
        UPDATE raw.companies SET source_file = '{name}' WHERE source_file IS NULL;
        COMMIT;
    """
    psql(env, sql=sql)


def sql_files_for(folder: str, only: list[str] | None) -> list[Path]:
    directory = SQL_ROOT / folder
    if only is not None:
        return [directory / name for name in only]
    return sorted(directory.glob("*.sql"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-raw", action="store_true",
                        help="skip reloading the raw files (minutes faster)")
    parser.add_argument("--only", metavar="LAYER",
                        help="run one layer only, e.g. staging")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan without running anything")
    args = parser.parse_args()

    env = read_env()
    started = time.time()
    failures = 0

    print(f"Project: {PROJECT_ROOT}")
    print(f"Database: {env.get('POSTGRES_DB')} in container {CONTAINER}\n")

    raw_files = find_raw_files()
    if not args.skip_raw and args.only is None:
        if not raw_files["register"] or not raw_files["companies"]:
            print("ERROR: raw data files not found in data/raw.")
            print("  Expected a register CSV (SP_*Worker*Register*.csv) and")
            print("  a Companies House CSV (BasicCompanyData*.csv).")
            print("  See data/README.md for where to download them.")
            return 1

    for label, folder, only_files in LAYERS:
        if args.only and args.only != label:
            continue
        print(f"=== {label} ===")

        for path in sql_files_for(folder, only_files):
            if args.dry_run:
                print(f"  would run {path.relative_to(PROJECT_ROOT)}")
                continue
            step_started = time.time()
            try:
                output = psql(env, sql_file=path)
                print(f"  ok   {path.name:<42} {time.time() - step_started:6.1f}s")
                # The quality layer's whole purpose is its output. The first
                # version of this script ran the checks, printed "ok", and
                # threw the PASS/FAIL table away - a pipeline that silently
                # discards the evidence it was built to produce.
                if label == "quality":
                    print()
                    print(output.rstrip())
                    print()
                    if " FAIL" in output:
                        failures += 1
                        print("  ^^ at least one check FAILED")
            except RuntimeError as error:
                failures += 1
                print(f"  FAIL {path.name}\n{error}")
                return 1

        # The raw loads happen after the raw DDL, since the tables must exist.
        if label == "raw-ddl" and not args.skip_raw:
            for path in raw_files["register"]:
                if args.dry_run:
                    print(f"  would load {path.name}")
                    continue
                step_started = time.time()
                load_register(env, path)
                print(f"  ok   load {path.name:<37} {time.time() - step_started:6.1f}s")
            for path in raw_files["companies"]:
                if args.dry_run:
                    print(f"  would load {path.name}")
                    continue
                step_started = time.time()
                load_companies(env, path)
                print(f"  ok   load {path.name:<37} {time.time() - step_started:6.1f}s")

        # History is applied once per snapshot found, oldest first, so that
        # SCD2 versions open and close in publication order.
        if label == "snapshots" and not args.dry_run:
            for path in raw_files["register"]:
                date = snapshot_date_from(path.name)
                if date is None:
                    print(f"  skip {path.name}: no date in filename")
                    continue
                output = psql(env, sql=(
                    f"SELECT * FROM marts.apply_employer_snapshot('marts', DATE '{date}');"
                ))
                numbers = output.strip().splitlines()[2].strip()
                print(f"  ok   history {date}  (closed | opened) = {numbers}")

        print()

    if args.dry_run:
        print("Dry run: nothing was executed.")
        return 0

    print(f"Finished in {time.time() - started:.1f}s with {failures} failure(s).")
    print("\nRe-read the quality output above: any FAIL line means the warehouse")
    print("is not in a state worth drawing conclusions from.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
