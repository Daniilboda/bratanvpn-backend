"""Convert architecture Markdown docs to readable PDFs (Cyrillic via Arial)."""

from __future__ import annotations

import re
from pathlib import Path

from fpdf import FPDF

DOCS = Path(__file__).resolve().parent
FONT = Path(r"C:\Windows\Fonts\arial.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\arialbd.ttf")


class DocPDF(FPDF):
    def footer(self) -> None:
        self.set_y(-12)
        self.set_font("ArialDoc", size=8)
        self.set_text_color(110, 110, 110)
        self.cell(0, 8, str(self.page_no()), align="C")


def _clean(text: str) -> str:
    replacements = {
        "\u00a0": " ",
        "—": "-",
        "–": "-",
        "→": "->",
        "◄": "<",
        "►": ">",
        "│": "|",
        "├": "+",
        "└": "+",
        "─": "-",
        "┌": "+",
        "┐": "+",
        "┘": "+",
        "┴": "+",
        "┬": "+",
        "┼": "+",
        "▼": "v",
        "•": "-",
        "**": "",
        "`": "",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    return text


def md_to_pdf(md_path: Path, pdf_path: Path, title: str, *, landscape: bool = False) -> None:
    text = md_path.read_text(encoding="utf-8")
    orientation = "L" if landscape else "P"
    pdf = DocPDF(orientation=orientation, format="A4")
    pdf.set_auto_page_break(auto=True, margin=14)
    pdf.add_page()
    pdf.add_font("ArialDoc", "", str(FONT))
    pdf.add_font("ArialDoc", "B", str(FONT_BOLD))
    pdf.set_margins(14, 14, 14)

    usable = pdf.epw

    pdf.set_font("ArialDoc", "B", 16)
    pdf.set_text_color(15, 15, 15)
    pdf.multi_cell(usable, 9, _clean(title))
    pdf.ln(2)
    pdf.set_draw_color(40, 40, 40)
    y = pdf.get_y()
    pdf.line(14, y, 14 + usable, y)
    pdf.ln(5)

    in_code = False

    for raw in text.splitlines():
        line = raw.rstrip()

        if line.startswith("```"):
            in_code = not in_code
            if not in_code:
                pdf.ln(2)
            continue

        if in_code:
            safe = _clean(line)
            # Split "path — description" style for readability
            if " - " in safe or " — " in line:
                # already cleaned emdash to -
                parts = re.split(r"\s+-\s+", safe, maxsplit=1)
                path_part = parts[0]
                desc_part = parts[1] if len(parts) > 1 else ""
                pdf.set_font("ArialDoc", size=8)
                pdf.set_text_color(20, 20, 20)
                pdf.multi_cell(usable, 4, path_part)
                if desc_part:
                    pdf.set_font("ArialDoc", size=8)
                    pdf.set_text_color(80, 80, 80)
                    pdf.set_x(20)
                    pdf.multi_cell(usable - 6, 4, desc_part)
            else:
                pdf.set_font("ArialDoc", size=7.5)
                pdf.set_text_color(25, 25, 25)
                pdf.multi_cell(usable, 3.8, safe if safe else " ")
            continue

        if not line.strip():
            pdf.ln(2.5)
            continue

        if line.startswith("# "):
            pdf.ln(2)
            pdf.set_font("ArialDoc", "B", 14)
            pdf.set_text_color(10, 10, 10)
            pdf.multi_cell(usable, 7, _clean(line[2:]))
            pdf.ln(1)
            continue

        if line.startswith("## "):
            pdf.ln(3)
            pdf.set_font("ArialDoc", "B", 12)
            pdf.set_text_color(20, 20, 20)
            pdf.multi_cell(usable, 6.5, _clean(line[3:]))
            pdf.ln(1)
            continue

        if line.startswith("### "):
            pdf.ln(2)
            pdf.set_font("ArialDoc", "B", 10.5)
            pdf.set_text_color(35, 35, 35)
            pdf.multi_cell(usable, 5.5, _clean(line[4:]))
            pdf.ln(0.5)
            continue

        if line.startswith("|") and "---" not in line:
            cells = [c.strip() for c in line.strip("|").split("|")]
            pdf.set_font("ArialDoc", size=8.5)
            pdf.set_text_color(30, 30, 30)
            pdf.multi_cell(usable, 4.5, _clean(" | ".join(cells)))
            continue

        if re.match(r"^\|?\s*-{3,}", line):
            continue

        if re.match(r"^[\s]*[-*]\s+", line):
            content = re.sub(r"^[\s]*[-*]\s+", "", line)
            pdf.set_font("ArialDoc", size=10)
            pdf.set_text_color(30, 30, 30)
            pdf.multi_cell(usable, 5, _clean(f"- {content}"))
            continue

        pdf.set_font("ArialDoc", size=10)
        pdf.set_text_color(30, 30, 30)
        pdf.multi_cell(usable, 5, _clean(line))

    pdf.output(str(pdf_path))
    print(f"Wrote {pdf_path} ({pdf_path.stat().st_size} bytes)")


def main() -> None:
    if not FONT.exists() or not FONT_BOLD.exists():
        raise SystemExit(f"Windows Arial fonts not found: {FONT}")

    md_to_pdf(
        DOCS / "PROJECT_TREE.md",
        DOCS / "PROJECT_TREE.pdf",
        "BratanVPN — дерево проекта (с описаниями файлов)",
        landscape=True,
    )
    md_to_pdf(
        DOCS / "ARCHITECTURE_MAP.md",
        DOCS / "ARCHITECTURE_MAP.pdf",
        "BratanVPN — карта архитектуры проекта",
        landscape=False,
    )


if __name__ == "__main__":
    main()
