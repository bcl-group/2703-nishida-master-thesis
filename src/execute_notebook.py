#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import traceback
from pathlib import Path
from typing import Any

import nbformat
from nbclient import NotebookClient
from nbclient.exceptions import CellExecutionError


def build_error_paths(output_notebook: Path) -> tuple[Path, Path]:
    base = output_notebook.with_suffix("")
    return base.with_suffix(".error.md"), base.with_suffix(".error.json")


def cell_source(cell: dict[str, Any]) -> str:
    return str(cell.get("source", "")).rstrip()


def cell_outputs_text(cell: dict[str, Any]) -> str:
    outputs = cell.get("outputs", [])
    parts: list[str] = []

    for out in outputs:
        output_type = out.get("output_type", "")

        if output_type == "stream":
            parts.append(str(out.get("text", "")))

        elif output_type in {"execute_result", "display_data"}:
            data = out.get("data", {})
            if "text/plain" in data:
                value = data["text/plain"]
                if isinstance(value, list):
                    parts.append("".join(map(str, value)))
                else:
                    parts.append(str(value))

        elif output_type == "error":
            tb = out.get("traceback", [])
            if tb:
                parts.append("\n".join(map(str, tb)))
            else:
                parts.append(f"{out.get('ename', '')}: {out.get('evalue', '')}")

    return "\n".join(parts).strip()


def write_error_markdown(
    md_path: Path,
    notebook_path: Path,
    output_path: Path,
    kernel_name: str,
    failing_index: int | None,
    failing_cell: dict[str, Any] | None,
    error_text: str,
) -> None:
    lines: list[str] = []
    lines.append(f"# Notebook execution failed")
    lines.append("")
    lines.append(f"- notebook: `{notebook_path}`")
    lines.append(f"- output: `{output_path}`")
    lines.append(f"- kernel: `{kernel_name}`")
    lines.append(f"- failing_cell_index: `{failing_index}`")
    lines.append("")

    if failing_cell is not None:
        lines.append("## Failing cell source")
        lines.append("```python")
        lines.append(cell_source(failing_cell))
        lines.append("```")
        lines.append("")

        outputs_text = cell_outputs_text(failing_cell)
        if outputs_text:
            lines.append("## Cell outputs before failure")
            lines.append("```text")
            lines.append(outputs_text)
            lines.append("```")
            lines.append("")

    lines.append("## Traceback")
    lines.append("```text")
    lines.append(error_text.rstrip())
    lines.append("```")
    lines.append("")

    md_path.write_text("\n".join(lines), encoding="utf-8")


def write_error_json(
    json_path: Path,
    notebook_path: Path,
    output_path: Path,
    kernel_name: str,
    failing_index: int | None,
    failing_cell: dict[str, Any] | None,
    error_text: str,
) -> None:
    payload = {
        "notebook": str(notebook_path),
        "output": str(output_path),
        "kernel": kernel_name,
        "failing_cell_index": failing_index,
        "failing_cell_source": cell_source(failing_cell) if failing_cell is not None else None,
        "error": error_text,
    }
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def find_failing_cell(nb: Any) -> tuple[int | None, dict[str, Any] | None]:
    for i, cell in enumerate(nb.cells):
        if cell.get("cell_type") != "code":
            continue

        for out in cell.get("outputs", []):
            if out.get("output_type") == "error":
                return i, cell

    return None, None


def execute_notebook(notebook_path: Path, kernel_name: str, output_path: Path) -> int:
    if not notebook_path.exists():
        raise FileNotFoundError(f"Notebook not found: {notebook_path}")

    with notebook_path.open("r", encoding="utf-8") as f:
        nb = nbformat.read(f, as_version=4)

    client = NotebookClient(
        nb,
        kernel_name=kernel_name,
        timeout=None,
        allow_errors=False,
        record_timing=True,
    )

    error_md_path, error_json_path = build_error_paths(output_path)

    try:
        client.execute(cwd=str(notebook_path.parent))

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as f:
            nbformat.write(nb, f)

        if error_md_path.exists():
            error_md_path.unlink()
        if error_json_path.exists():
            error_json_path.unlink()

        print(f"[execute_notebook] success: {output_path}")
        return 0

    except CellExecutionError as e:
        failing_index, failing_cell = find_failing_cell(nb)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as f:
            nbformat.write(nb, f)

        error_text = "".join(
            traceback.format_exception(type(e), e, e.__traceback__)
        )

        write_error_markdown(
            error_md_path,
            notebook_path,
            output_path,
            kernel_name,
            failing_index,
            failing_cell,
            error_text,
        )
        write_error_json(
            error_json_path,
            notebook_path,
            output_path,
            kernel_name,
            failing_index,
            failing_cell,
            error_text,
        )

        print(f"[execute_notebook] failed: {error_md_path}")
        return 1

    except Exception as e:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as f:
            nbformat.write(nb, f)

        error_text = "".join(
            traceback.format_exception(type(e), e, e.__traceback__)
        )

        write_error_markdown(
            error_md_path,
            notebook_path,
            output_path,
            kernel_name,
            None,
            None,
            error_text,
        )
        write_error_json(
            error_json_path,
            notebook_path,
            output_path,
            kernel_name,
            None,
            None,
            error_text,
        )

        print(f"[execute_notebook] failed: {error_md_path}")
        return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--notebook", required=True, help="Path to input notebook")
    parser.add_argument("--kernel", required=True, help="Kernel name")
    parser.add_argument("--output", required=True, help="Path to executed notebook")
    args = parser.parse_args()

    notebook_path = Path(args.notebook).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    kernel_name = args.kernel

    return execute_notebook(notebook_path, kernel_name, output_path)


if __name__ == "__main__":
    raise SystemExit(main())