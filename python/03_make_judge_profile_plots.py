from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker


BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

plt.rcParams.update({
    "font.size": 12,
    "axes.labelsize": 12,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
    "legend.fontsize": 11,
})


def read_csv(name: str) -> pd.DataFrame:
    path = CSV_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"CSV not found: {path}")
    return pd.read_csv(path)


def clean_category(series: pd.Series, missing_label: str = "Missing") -> pd.Series:
    return (
        series.astype("string")
        .fillna(missing_label)
        .replace({"<NA>": missing_label, "nan": missing_label, "None": missing_label})
        .str.strip()
        .replace("", missing_label)
    )


def recode_gender(series: pd.Series) -> pd.Series:
    mapping = {
        "m": "Male",
        "f": "Female",
        "male": "Male",
        "female": "Female",
        "missing": "Missing",
    }
    cleaned = clean_category(series, missing_label="Missing").str.lower()
    return cleaned.map(lambda x: mapping.get(x, x.title()))


def recode_activity(series: pd.Series) -> pd.Series:
    mapping = {
        "active": "Active",
        "not_active": "Not active",
        "missing": "Missing",
    }
    cleaned = clean_category(series, missing_label="Missing").str.lower()
    return cleaned.map(lambda x: mapping.get(x, x.replace("_", " ").title()))


def recode_party(series: pd.Series) -> pd.Series:
    mapping = {
        "d": "Democratic",
        "r": "Republican",
        "missing": "Missing",
        "multiple": "Multiple",
    }
    cleaned = clean_category(series, missing_label="Missing").str.lower()
    return cleaned.map(lambda x: mapping.get(x, x.upper() if len(x) == 1 else x.title()))


def collapse_political_party(series: pd.Series) -> pd.Series:
    cleaned = recode_party(series)
    major = {"Democratic", "Republican", "Missing", "Multiple"}
    return cleaned.apply(lambda x: x if x in major else "Other")


def shorten_labels(series: pd.Series, max_len: int = 45) -> pd.Series:
    return series.astype(str).apply(
        lambda s: s if len(s) <= max_len else s[: max_len - 3] + "..."
    )


def format_plain_numbers(ax, axis: str = "y") -> None:
    if axis == "y":
        ax.ticklabel_format(style="plain", axis="y")
        ax.yaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))
    elif axis == "x":
        ax.ticklabel_format(style="plain", axis="x")
        ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))


def apply_common_style(ax, grid_axis: str = "y") -> None:
    ax.grid(axis=grid_axis, linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)


def add_bar_labels_vertical(ax, values: pd.Series, total: float | None = None) -> None:
    ymax = ax.get_ylim()[1]
    offset = ymax * 0.01

    for bar, value in zip(ax.patches, values):
        if pd.isna(value):
            continue

        if total is not None and total > 0:
            pct = 100 * value / total
            label = f"{int(value):,}\n({pct:.1f}%)"
        else:
            label = f"{int(value):,}"

        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + offset,
            label,
            ha="center",
            va="bottom",
            fontsize=10,
        )


def add_bar_labels_horizontal(ax, values: pd.Series, total: float | None = None) -> None:
    xmax = ax.get_xlim()[1]
    offset = xmax * 0.01

    for bar, value in zip(ax.patches, values):
        if pd.isna(value):
            continue

        if total is not None and total > 0:
            pct = 100 * value / total
            label = f"{int(value):,} ({pct:.1f}%)"
        else:
            label = f"{int(value):,}"

        ax.text(
            bar.get_width() + offset,
            bar.get_y() + bar.get_height() / 2,
            label,
            ha="left",
            va="center",
            fontsize=10,
        )


def save_bar_plot(
    df: pd.DataFrame,
    category_col: str,
    value_col: str,
    outfile: str,
    xlabel: str,
    ylabel: str,
    horizontal: bool = False,
    rotate_x: bool = False,
    sort_desc: bool = True,
    top_n: int | None = None,
    category_order: list[str] | None = None,
    show_percent_labels: bool = False,
) -> None:
    plot_df = df.copy()

    plot_df[value_col] = pd.to_numeric(plot_df[value_col], errors="coerce")
    plot_df = plot_df.dropna(subset=[value_col])

    if category_col in plot_df.columns:
        plot_df[category_col] = clean_category(plot_df[category_col])

    if category_order is not None:
        order_map = {cat: i for i, cat in enumerate(category_order)}
        plot_df["_order"] = plot_df[category_col].map(lambda x: order_map.get(x, 999))
        plot_df = plot_df.sort_values(["_order", value_col], ascending=[True, False])
        plot_df = plot_df.drop(columns="_order")
    else:
        plot_df = plot_df.sort_values(value_col, ascending=not sort_desc)

    if top_n is not None:
        plot_df = plot_df.head(top_n)

    if horizontal:
        plot_df = plot_df.sort_values(value_col, ascending=True)
        fig, ax = plt.subplots(figsize=(10, max(5.5, 0.55 * len(plot_df))))
        ax.barh(plot_df[category_col].astype(str), plot_df[value_col])

        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)

        xmax = plot_df[value_col].max()
        ax.set_xlim(0, xmax * 1.22)

        apply_common_style(ax, grid_axis="x")
        format_plain_numbers(ax, axis="x")

        if show_percent_labels:
            add_bar_labels_horizontal(ax, plot_df[value_col], total=plot_df[value_col].sum())

    else:
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.bar(plot_df[category_col].astype(str), plot_df[value_col])

        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)

        ymax = plot_df[value_col].max()
        ax.set_ylim(0, ymax * 1.18)

        apply_common_style(ax, grid_axis="y")
        format_plain_numbers(ax, axis="y")

        if rotate_x:
            plt.xticks(rotation=45, ha="right")

        if show_percent_labels:
            add_bar_labels_vertical(ax, plot_df[value_col], total=plot_df[value_col].sum())

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def save_grouped_bar_plot(
    df: pd.DataFrame,
    index_col: str,
    column_col: str,
    value_col: str,
    outfile: str,
    xlabel: str,
    ylabel: str,
    index_order: list[str] | None = None,
    column_order: list[str] | None = None,
) -> None:
    plot_df = df.copy()
    plot_df[index_col] = clean_category(plot_df[index_col])
    plot_df[column_col] = clean_category(plot_df[column_col])
    plot_df[value_col] = pd.to_numeric(plot_df[value_col], errors="coerce")

    pivot_df = plot_df.pivot(index=index_col, columns=column_col, values=value_col).fillna(0)

    if index_order is not None:
        pivot_df = pivot_df.reindex(index=[x for x in index_order if x in pivot_df.index])

    if column_order is not None:
        existing_cols = [x for x in column_order if x in pivot_df.columns]
        remaining_cols = [x for x in pivot_df.columns if x not in existing_cols]
        pivot_df = pivot_df[existing_cols + remaining_cols]

    fig, ax = plt.subplots(figsize=(8.5, 6))
    pivot_df.plot(kind="bar", ax=ax)

    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)

    apply_common_style(ax, grid_axis="y")
    format_plain_numbers(ax, axis="y")
    plt.xticks(rotation=45, ha="right")

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def main() -> None:
    # 1. Gender distribution
    gender = read_csv("judge_gender_distribution.csv")
    gender["gender_clean"] = recode_gender(gender["gender_clean"])
    save_bar_plot(
        gender,
        category_col="gender_clean",
        value_col="n",
        outfile="judge_gender_distribution.png",
        xlabel="Gender",
        ylabel="Number of persons",
        horizontal=False,
        rotate_x=False,
        sort_desc=False,
        category_order=["Male", "Female", "Missing"],
        show_percent_labels=True,
    )

    # 2. Activity status
    activity = read_csv("judge_activity_status.csv")
    activity["activity_status"] = recode_activity(activity["activity_status"])
    save_bar_plot(
        activity,
        category_col="activity_status",
        value_col="n",
        outfile="judge_activity_status.png",
        xlabel="Activity status",
        ylabel="Number of persons",
        horizontal=False,
        rotate_x=False,
        sort_desc=False,
        category_order=["Active", "Not active", "Missing"],
    )

    # 3. Political party distribution
    political = read_csv("judge_political_party_distribution.csv")
    political["political_party_clean"] = collapse_political_party(political["political_party_clean"])
    political = (
        political.groupby("political_party_clean", as_index=False)["n"]
        .sum()
    )

    save_bar_plot(
        political,
        category_col="political_party_clean",
        value_col="n",
        outfile="judge_political_party_distribution.png",
        xlabel="Number of records",
        ylabel="Political party",
        horizontal=True,
        sort_desc=True,
        show_percent_labels=True,
    )

    # 4. Degree level distribution
    degree = read_csv("judge_degree_level_distribution.csv")
    degree["degree_level_clean"] = clean_category(degree["degree_level_clean"])
    save_bar_plot(
        degree,
        category_col="degree_level_clean",
        value_col="n",
        outfile="judge_degree_level_distribution.png",
        xlabel="Degree level",
        ylabel="Number of education records",
        horizontal=False,
        rotate_x=True,
        sort_desc=True,
    )

    # 5. Top 10 schools by education count
    schools = read_csv("judge_top25_schools.csv")
    schools = schools.sort_values("education_count", ascending=False).head(10).copy()
    schools["name"] = shorten_labels(schools["name"], max_len=50)
    save_bar_plot(
        schools,
        category_col="name",
        value_col="education_count",
        outfile="judge_top10_schools.png",
        xlabel="Number of education records",
        ylabel="School",
        horizontal=True,
        sort_desc=True,
    )

    # 6. Gender by activity status
    gender_activity = read_csv("judge_gender_by_activity_status.csv")
    gender_activity["gender_clean"] = recode_gender(gender_activity["gender_clean"])
    gender_activity["activity_status"] = recode_activity(gender_activity["activity_status"])
    save_grouped_bar_plot(
        gender_activity,
        index_col="gender_clean",
        column_col="activity_status",
        value_col="n",
        outfile="judge_gender_by_activity_status.png",
        xlabel="Gender",
        ylabel="Number of persons",
        index_order=["Male", "Female", "Missing"],
        column_order=["Active", "Not active", "Missing"],
    )

    print(f"Saved judge profile plots to: {FIG_DIR}")


if __name__ == "__main__":
    main()