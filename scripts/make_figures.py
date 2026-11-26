"""Generate the figures used in the README.

Why this is a committed script rather than a one-off: every figure has to be
regeneratable from the warehouse. A PNG nobody can reproduce is an assertion,
the same as a number nobody can reproduce.

Each figure is drawn from the same marts tables the analysis queries use, and
the SQL is kept beside the plot so the two cannot drift apart.

What is deliberately NOT plotted, and why
-----------------------------------------
* Rating breakdown. 98 of 142,356 licences are rated B - 0.07%. Any bar chart
  of that is either an invisible sliver or a rescaled axis that makes a rare
  thing look common. The table in the README states it honestly; a chart would
  not.
* Anything resting on fuzzy matches. A hand-checked sample of 24 suggests at
  least 21% of them are wrong. Plotting them would lend a precision the data
  does not have. Figures that use company attributes are restricted to exact
  matches and say so in the caption.
* Sector mix by town. The leading sector is often only 4-6% of a town, and
  several towns tie. A chart implies a clear winner where there is not one.

Usage
-----
    py scripts/make_figures.py
"""

from __future__ import annotations

import csv
import io
import subprocess
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display needed; this runs headless
import matplotlib.pyplot as plt  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FIGURE_DIR = PROJECT_ROOT / "docs" / "figures"
CONTAINER = "uk_employer_intel_pg"

# Colours chosen to stay legible on both GitHub themes, and distinguishable
# in greyscale and for the common forms of colour blindness.
INK = "#1b2733"
MUTED = "#8c9aa8"
ACCENT = "#1f6feb"
WARN = "#b54708"

# PNG metadata is set explicitly. Image files carry a software/author string
# that a grep over text files would never see.
PNG_METADATA = {"Software": "matplotlib", "Author": "Kritika Singh Chauhan"}


def read_env() -> dict[str, str]:
    env_path = PROJECT_ROOT / ".env"
    values: dict[str, str] = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def query(env: dict[str, str], sql: str) -> list[dict[str, str]]:
    """Run SQL and return rows as dicts.

    CSV output rather than a database driver, for the same reason
    run_pipeline.py shells out to psql: it keeps the project free of
    third-party database dependencies.
    """
    result = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql",
         "-U", env["POSTGRES_USER"], "-d", env["POSTGRES_DB"],
         "-v", "ON_ERROR_STOP=1", "--csv", "-c", sql],
        capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(f"query failed:\n{result.stderr.strip()}")
    return list(csv.DictReader(io.StringIO(result.stdout)))


def style(ax) -> None:
    """One consistent look: no chartjunk, no box, horizontal guides only."""
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(MUTED)
    ax.tick_params(colors=INK, length=0)
    ax.grid(axis="x", color="#e6eaee", linewidth=0.8)
    ax.set_axisbelow(True)


def save(fig, name: str) -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    path = FIGURE_DIR / name
    fig.savefig(path, dpi=160, bbox_inches="tight",
                facecolor="white", metadata=PNG_METADATA)
    plt.close(fig)
    print(f"  wrote {path.relative_to(PROJECT_ROOT)}")


# --------------------------------------------------------------------------
# Figure 1: where registered employers are
# --------------------------------------------------------------------------
def fig_employers_by_town(env) -> None:
    """Counts straight from the register. No matching involved, so this figure
    carries none of the matching uncertainty."""
    rows = query(env, """
        SELECT l.town, count(DISTINCT f.employer_key) AS employers
        FROM marts.fact_employer_snapshot f
        JOIN marts.dim_location l ON l.location_key = f.location_key
        WHERE NOT l.is_unknown
        GROUP BY l.town ORDER BY employers DESC LIMIT 15
    """)
    towns = [r["town"] for r in rows][::-1]
    counts = [int(r["employers"]) for r in rows][::-1]

    fig, ax = plt.subplots(figsize=(8, 5.5))
    colours = [ACCENT if t == "London" else MUTED for t in towns]
    ax.barh(towns, counts, color=colours, height=0.72)
    for town, count in zip(towns, counts):
        ax.text(count + max(counts) * 0.012, town, f"{count:,}",
                va="center", fontsize=9, color=INK)
    ax.set_xlim(0, max(counts) * 1.14)
    ax.set_xlabel("Registered employers", color=INK, fontsize=9)
    ax.set_title("London holds 28.6% of all registered employers",
                 color=INK, fontsize=12, loc="left", pad=12)
    style(ax)
    save(fig, "employers_by_town.png")


# --------------------------------------------------------------------------
# Figure 2: how concentrated the register is
# --------------------------------------------------------------------------
def fig_concentration(env) -> None:
    """Towns ranked by size, cumulative share of employers. Also from the
    register alone."""
    rows = query(env, """
        WITH by_town AS (
            SELECT l.town, count(DISTINCT f.employer_key) AS employers
            FROM marts.fact_employer_snapshot f
            JOIN marts.dim_location l ON l.location_key = f.location_key
            WHERE NOT l.is_unknown GROUP BY l.town
        )
        SELECT row_number() OVER (ORDER BY employers DESC) AS rank,
               round(100.0 * sum(employers) OVER (ORDER BY employers DESC
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                     / sum(employers) OVER (), 4) AS cumulative_pct
        FROM by_town ORDER BY rank
    """)
    ranks = [int(r["rank"]) for r in rows]
    cumulative = [float(r["cumulative_pct"]) for r in rows]
    total_towns = len(ranks)

    fig, ax = plt.subplots(figsize=(8, 4.8))
    ax.plot(ranks, cumulative, color=ACCENT, linewidth=2)
    ax.fill_between(ranks, cumulative, color=ACCENT, alpha=0.08)

    # Mark the top decile, which is the headline figure in the README.
    decile = max(1, total_towns // 10)
    decile_pct = cumulative[decile - 1]
    ax.plot([decile], [decile_pct], "o", color=WARN, markersize=6)
    ax.annotate(
        f"Top 10% of towns ({decile:,} of {total_towns:,})\nhold {decile_pct:.1f}% of employers",
        xy=(decile, decile_pct), xytext=(total_towns * 0.22, 55),
        color=INK, fontsize=9,
        arrowprops=dict(arrowstyle="-", color=WARN, linewidth=1),
    )
    ax.set_xlabel("Towns, ranked largest first", color=INK, fontsize=9)
    ax.set_ylabel("Cumulative % of employers", color=INK, fontsize=9)
    ax.set_ylim(0, 103)
    ax.set_xlim(0, total_towns)
    ax.set_title("A small number of towns account for almost all employers",
                 color=INK, fontsize=12, loc="left", pad=12)
    style(ax)
    ax.grid(axis="y", color="#e6eaee", linewidth=0.8)
    save(fig, "concentration.png")


# --------------------------------------------------------------------------
# Figure 3: match coverage - the honest one
# --------------------------------------------------------------------------
def fig_match_outcome(env) -> None:
    """Shows what the matching could and could not do, including the fifth of
    names it could not place. This figure exists to stop the rest of the
    README being read as complete coverage."""
    rows = query(env, """
        SELECT match_method, count(*) AS names
        FROM marts.employer_company_match GROUP BY 1
    """)
    counts = {r["match_method"]: int(r["names"]) for r in rows}
    total = sum(counts.values())

    order = [
        ("exact", "Exact name match", ACCENT),
        ("fuzzy", "Fuzzy match (≥ 21% of these are wrong)", WARN),
        ("ambiguous", "Ambiguous: several companies share the name", "#d4a72c"),
        ("none", "No company found", MUTED),
    ]

    fig, ax = plt.subplots(figsize=(8, 2.6))
    left = 0.0
    for key, label, colour in order:
        value = counts.get(key, 0)
        width = 100.0 * value / total
        ax.barh([0], [width], left=left, color=colour, height=0.55)
        if width > 4:
            ax.text(left + width / 2, 0, f"{width:.1f}%",
                    ha="center", va="center", color="white", fontsize=10)
        left += width

    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for _, _, c in order]
    labels = [f"{lab}  —  {counts.get(k, 0):,}" for k, lab, _ in order]
    ax.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, -0.25),
              ncol=2, frameon=False, fontsize=9, labelcolor=INK)
    ax.set_yticks([])
    ax.set_xlim(0, 100)
    ax.set_xlabel("Share of the 126,963 distinct employer names",
                  color=INK, fontsize=9)
    ax.set_title("One name in five could not be linked to a company",
                 color=INK, fontsize=12, loc="left", pad=12)
    style(ax)
    ax.grid(False)
    save(fig, "match_outcome.png")


# --------------------------------------------------------------------------
# Figure 4: technology concentration
# --------------------------------------------------------------------------
def fig_technology_share(env) -> None:
    """Exact matches only. The caption in the README says so, because the
    denominator here is 'employers we could classify', not 'all employers'."""
    rows = query(env, """
        WITH tech AS (
            SELECT l.town,
                   count(DISTINCT f.employer_key)
                     FILTER (WHERE t.company_key IS NOT NULL) AS tech_employers,
                   count(DISTINCT f.employer_key)              AS all_employers
            FROM marts.fact_employer_snapshot f
            JOIN marts.dim_location l ON l.location_key = f.location_key
            LEFT JOIN analysis.v_technology_company t ON t.company_key = f.company_key
            WHERE NOT l.is_unknown
            GROUP BY l.town
        )
        SELECT town, tech_employers, all_employers,
               round(100.0 * tech_employers / all_employers, 1) AS pct
        FROM tech
        WHERE all_employers >= 300 AND tech_employers > 0
        ORDER BY pct DESC LIMIT 12
    """)
    towns = [r["town"] for r in rows][::-1]
    pct = [float(r["pct"]) for r in rows][::-1]
    counts = [int(r["tech_employers"]) for r in rows][::-1]

    fig, ax = plt.subplots(figsize=(8, 5))
    colours = [ACCENT if t in ("Reading", "London") else MUTED for t in towns]
    ax.barh(towns, pct, color=colours, height=0.72)
    for town, value, count in zip(towns, pct, counts):
        ax.text(value + 0.4, town, f"{value:.1f}%  ({count:,})",
                va="center", fontsize=9, color=INK)
    ax.set_xlim(0, max(pct) * 1.3)
    ax.set_xlabel("% of the town's registered employers in the technology sector",
                  color=INK, fontsize=9)
    ax.set_title("Reading is the most technology-dense town, not London",
                 color=INK, fontsize=12, loc="left", pad=12)
    style(ax)
    save(fig, "technology_share.png")


# --------------------------------------------------------------------------
# Figure 5: incorporation years, with the artefact marked
# --------------------------------------------------------------------------
def fig_incorporations(env) -> None:
    """The recent years are NOT a decline. A company incorporated in 2026 has
    had almost no time to obtain a licence, so the tail is an artefact of when
    the snapshot was taken. The figure shades those years and says so on the
    chart itself, because a caption below an image is easy to miss and the
    chart will be screenshotted away from its caption."""
    rows = query(env, """
        SELECT extract(year FROM c.incorporation_date)::int AS year,
               count(DISTINCT f.employer_key) AS employers
        FROM marts.fact_employer_snapshot f
        JOIN marts.dim_company c ON c.company_key = f.company_key
        WHERE c.match_method = 'exact' AND c.incorporation_date IS NOT NULL
          AND c.incorporation_date >= CURRENT_DATE - INTERVAL '20 years'
        GROUP BY 1 ORDER BY 1
    """)
    years = [int(r["year"]) for r in rows]
    counts = [int(r["employers"]) for r in rows]

    # The last three years are incomplete for the reason above.
    cutoff = max(years) - 2
    colours = [WARN if y >= cutoff else ACCENT for y in years]

    fig, ax = plt.subplots(figsize=(8, 4.6))
    ax.bar(years, counts, color=colours, width=0.72)
    ax.axvspan(cutoff - 0.5, max(years) + 0.5, color=WARN, alpha=0.07)
    # Placed top-left, where the early years leave the plot empty. An earlier
    # version put it beside the shaded band and it landed on top of the bars.
    ax.annotate(
        "The shaded years are not a decline:\ncompanies formed recently have had\nlittle time to obtain a licence",
        xy=(min(years) + 0.2, max(counts) * 1.02), fontsize=9, color=WARN,
        ha="left", va="top",
    )
    ax.set_ylim(0, max(counts) * 1.18)
    ax.set_xlabel("Year of incorporation", color=INK, fontsize=9)
    ax.set_ylabel("Employers", color=INK, fontsize=9)
    ax.set_title("Incorporation years of companies on the register today",
                 color=INK, fontsize=12, loc="left", pad=12)
    style(ax)
    ax.grid(axis="y", color="#e6eaee", linewidth=0.8)
    ax.grid(axis="x", visible=False)
    save(fig, "incorporations_by_year.png")


def main() -> int:
    env = read_env()
    print("Generating figures from the warehouse...")
    for figure in (fig_employers_by_town, fig_concentration, fig_match_outcome,
                   fig_technology_share, fig_incorporations):
        figure(env)
    print(f"\nDone. {len(list(FIGURE_DIR.glob('*.png')))} figures in "
          f"{FIGURE_DIR.relative_to(PROJECT_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
