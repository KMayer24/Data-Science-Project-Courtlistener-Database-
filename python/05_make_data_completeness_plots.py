from pathlib import Path
import textwrap

import pandas as pd
import matplotlib.pyplot as plt


BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_PATH = BASE / "cleaned_csv" / "data_completeness_overview.csv"
TABLE_LEVEL_PATH = BASE / "cleaned_csv" / "data_completeness_table_level.csv"
TEXT_AUDIT_PATH = BASE / "cleaned_csv" / "search_opinion_text_audit_summary.csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

BLUE = "#0072B2"
MISSING_COLOR = "#B3B3B3"
GRID_COLOR = "#d7dce2"
TEXT_COLOR = "#20252b"

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Latin Modern Roman", "DejaVu Serif"],
    "font.size": 10,
    "axes.labelsize": 10,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "legend.fontsize": 9,
    "legend.title_fontsize": 9.5,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.edgecolor": "#707780",
    "text.color": TEXT_COLOR,
    "axes.labelcolor": TEXT_COLOR,
    "xtick.color": TEXT_COLOR,
    "ytick.color": TEXT_COLOR,
})


CORE_VARIABLES = {
    "people_db_person": [
        "name_first",
        "name_last",
        "date_dob",
        "gender",
        "religion",
        "has_photo",
    ],
    "people_db_position": [
        "position_type",
        "job_title",
        "organization_name",
        "date_start",
        "date_termination",
        "how_selected",
        "court_id",
    ],
    "people_db_education": [
        "degree_level",
        "degree_detail",
        "degree_year",
        "school_id",
    ],
    "people_db_school": [
        "name",
        "ein",
    ],
    "people_db_politicalaffiliation": [
        "political_party",
        "date_start",
        "date_end",
    ],
    "search_court": [
        "full_name",
        "short_name",
        "jurisdiction",
        "parent_court_id",
    ],
    "search_docket": [
        "court_id",
        "date_filed",
        "case_name",
        "case_name_short",
        "jurisdiction_type",
        "nature_of_suit",
    ],
    "search_opinioncluster": [
        "date_filed",
        "case_name",
        "precedential_status",
        "disposition",
        "citation_count",
    ],
    "search_citation": [
        "reporter",
        "page",
        "type",
        "cluster_id",
    ],
    "search_opinion": [
        "type",
        "author_id",
        "author_str",
        "cluster_id",
        "per_curiam",
        "page_count",
        "any_text_available",
    ],
}


DETAIL_TABLES = [
    "people_db_person",
    "people_db_position",
    "people_db_education",
    "people_db_school",
    "people_db_politicalaffiliation",
    "search_court",
    "search_docket",
    "search_opinioncluster",
    "search_citation",
    "search_opinion",
]


DISPLAY_NAMES = {
    "people_db_person": "Persons",
    "people_db_position": "Judicial positions",
    "people_db_education": "Education records",
    "people_db_school": "Schools",
    "people_db_politicalaffiliation": "Political affiliations",
    "search_court": "Courts",
    "search_docket": "Dockets",
    "search_opinioncluster": "Opinion clusters",
    "search_citation": "Citation metadata",
    "search_opinion": "Opinions",
}


def wrap_label(label: str, width: int = 24) -> str:
    return "\n".join(textwrap.wrap(label, width=width, break_long_words=False))


def read_completeness_data() -> pd.DataFrame:
    if not CSV_PATH.exists():
        raise FileNotFoundError(f"CSV not found: {CSV_PATH}")

    df = pd.read_csv(CSV_PATH)

    for col in ["missing_pct", "completeness_pct", "total_rows", "missing_count"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    return df


def read_table_level_data() -> pd.DataFrame:
    if not TABLE_LEVEL_PATH.exists():
        raise FileNotFoundError(f"CSV not found: {TABLE_LEVEL_PATH}")

    df = pd.read_csv(TABLE_LEVEL_PATH)

    for col in [
        "n_variables_checked",
        "avg_completeness_pct",
        "median_completeness_pct",
        "min_completeness_pct",
        "max_completeness_pct",
        "n_below_50_pct",
        "n_full_100_pct",
    ]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    return df


def add_any_text_available(df: pd.DataFrame) -> pd.DataFrame:
    already_exists = (
        (df["table_name"] == "search_opinion")
        & (df["variable_name"] == "any_text_available")
    ).any()

    if already_exists:
        return df

    if not TEXT_AUDIT_PATH.exists():
        print("Warning: text audit summary not found; cannot add any_text_available.")
        return df

    audit = pd.read_csv(TEXT_AUDIT_PATH)
    row = audit[audit["field_name"] == "any_text_available"].copy()

    if row.empty:
        print("Warning: any_text_available not found in text audit summary.")
        return df

    total_rows = pd.to_numeric(row["total_rows"].iloc[0], errors="coerce")
    non_empty_rows = pd.to_numeric(row["non_empty_rows"].iloc[0], errors="coerce")
    completeness_pct = pd.to_numeric(row["non_empty_pct"].iloc[0], errors="coerce")
    missing_count = total_rows - non_empty_rows
    missing_pct = round(100 - completeness_pct, 2)

    synthetic_row = pd.DataFrame(
        {
            "table_name": ["search_opinion"],
            "variable_name": ["any_text_available"],
            "total_rows": [total_rows],
            "missing_count": [missing_count],
            "missing_pct": [missing_pct],
            "completeness_pct": [completeness_pct],
        }
    )

    return pd.concat([df, synthetic_row], ignore_index=True)


def filter_to_core_variables(df: pd.DataFrame) -> pd.DataFrame:
    keep_rows = []
    for table_name, variables in CORE_VARIABLES.items():
        subset = df[
            (df["table_name"] == table_name)
            & (df["variable_name"].isin(variables))
        ].copy()
        keep_rows.append(subset)

    result = pd.concat(keep_rows, ignore_index=True)

    for table_name, variables in CORE_VARIABLES.items():
        existing = set(result.loc[result["table_name"] == table_name, "variable_name"])
        missing = [v for v in variables if v not in existing]
        if missing:
            print(f"Warning: missing variables for {table_name}: {missing}")

    return result


def apply_common_style(ax, xlabel: str) -> None:
    ax.set_xlim(0, 100)
    ax.set_xlabel(xlabel)
    ax.grid(axis="x", color=GRID_COLOR, linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)


def save_table_overview(table_level_df: pd.DataFrame) -> None:
    plot_df = (
        table_level_df.dropna(subset=["avg_completeness_pct"])
        .copy()
        .sort_values("avg_completeness_pct", ascending=True)
    )

    plot_df["table_label"] = plot_df["table_name"].map(DISPLAY_NAMES).fillna(plot_df["table_name"])

    fig, ax = plt.subplots(figsize=(6.6, 3.5))

    bars = ax.barh(
        plot_df["table_label"],
        plot_df["avg_completeness_pct"],
        color=BLUE,
        height=0.58,
    )

    apply_common_style(ax, "Average completeness of selected variables (%)")
    ax.set_xticks([0, 20, 40, 60, 80, 100])
    ax.set_ylabel("")

    for bar, value in zip(bars, plot_df["avg_completeness_pct"]):
        ax.text(
            value - 1.2,
            bar.get_y() + bar.get_height() / 2,
            f"{value:.1f}",
            ha="right",
            va="center",
            color="white",
            fontsize=8.5,
        )

    fig.subplots_adjust(left=0.25, right=0.985, bottom=0.18, top=0.98)
    plt.savefig(FIG_DIR / "core_completeness_by_table.png", dpi=300, bbox_inches="tight")
    plt.close()


def save_table_detail(core_df: pd.DataFrame, table_name: str) -> None:
    plot_df = (
        core_df[
            (core_df["table_name"] == table_name)
            & (core_df["completeness_pct"].notna())
        ]
        .copy()
        .sort_values("completeness_pct", ascending=True)
    )

    if plot_df.empty:
        print(f"Skipped {table_name}: no valid completeness values.")
        return

    plot_df["variable_label"] = plot_df["variable_name"].apply(lambda x: wrap_label(x, width=22))

    height = max(4.5, 0.7 * len(plot_df))
    fig, ax = plt.subplots(figsize=(9.5, height))

    ax.barh(
        plot_df["variable_label"],
        plot_df["completeness_pct"],
        color=BLUE,
        height=0.68,
        label="Completeness (%)",
    )
    ax.barh(
        plot_df["variable_label"],
        plot_df["missing_pct"],
        left=plot_df["completeness_pct"],
        color=MISSING_COLOR,
        height=0.68,
        label="Missingness (%)",
    )

    apply_common_style(ax, "Share of records (%)")
    ax.set_ylabel("")

    ax.legend(
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=2,
        frameon=False,
    )

    plt.tight_layout()
    plt.savefig(FIG_DIR / f"core_completeness_{table_name}.png", dpi=300, bbox_inches="tight")
    plt.close()


def save_search_opinion_text_audit() -> None:
    if not TEXT_AUDIT_PATH.exists():
        print("Skipped text audit plot: text audit summary CSV not found.")
        return

    df = pd.read_csv(TEXT_AUDIT_PATH)
    df["non_empty_pct"] = pd.to_numeric(df["non_empty_pct"], errors="coerce")
    df = df.dropna(subset=["non_empty_pct"]).copy()

    order = [
        "author_str",
        "plain_text",
        "html",
        "xml_harvard",
        "html_with_citations",
        "any_text_available",
    ]
    df = df[df["field_name"].isin(order)].copy()
    df["field_name"] = pd.Categorical(df["field_name"], categories=order, ordered=True)
    df = df.sort_values("field_name")

    df["missing_pct"] = 100 - df["non_empty_pct"]
    df["field_label"] = df["field_name"].apply(lambda x: wrap_label(x, width=22))

    fig, ax = plt.subplots(figsize=(9.5, 5.5))

    ax.barh(
        df["field_label"],
        df["non_empty_pct"],
        color=BLUE,
        height=0.68,
        label="Available / non-empty (%)",
    )
    ax.barh(
        df["field_label"],
        df["missing_pct"],
        left=df["non_empty_pct"],
        color=MISSING_COLOR,
        height=0.68,
        label="Missing (%)",
    )

    apply_common_style(ax, "Share of opinion records (%)")
    ax.set_ylabel("")

    ax.legend(
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=2,
        frameon=False,
    )

    plt.tight_layout()
    plt.savefig(FIG_DIR / "search_opinion_text_audit.png", dpi=300, bbox_inches="tight")
    plt.close()


def main() -> None:
    df = read_completeness_data()
    table_level_df = read_table_level_data()

    df = add_any_text_available(df)
    core_df = filter_to_core_variables(df)

    save_table_overview(table_level_df)

    for table_name in DETAIL_TABLES:
        save_table_detail(core_df, table_name)

    save_search_opinion_text_audit()

    print(f"Saved completeness plots to: {FIG_DIR}")


if __name__ == "__main__":
    main()
