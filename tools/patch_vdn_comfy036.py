#!/usr/bin/env python3
"""Compatibility patch for ComfyUI 0.36 + ComfyUI-VDN-H3-24GB.

ComfyUI 0.36 may return dense attention in a flattened or head-first layout
when VDN expects [seq, heads, head_dim]. This patch normalizes the tensor just
before the VDN softmax gate is applied.

The script is idempotent and creates a .comfy036-shape.bak backup once.
"""

from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "# ComfyUI 0.36 shape compatibility"

OLD = '''                    with prof_section("gate_apply_reshape", block_index):
                        flat = (softmax_out * gate.view(s, heads, 1).to(softmax_out.dtype)) \\
                            .reshape(s, -1)
'''

NEW = '''                    with prof_section("gate_apply_reshape", block_index):
                        # ComfyUI 0.36 shape compatibility:
                        # optimized_attention(..., skip_reshape=True) may return
                        # [seq, heads*head_dim] instead of [seq, heads, head_dim].
                        if softmax_out.ndim == 2:
                            if (softmax_out.shape[0] == s and
                                    softmax_out.shape[1] == heads * head_dim):
                                softmax_out = softmax_out.reshape(s, heads, head_dim)
                            else:
                                raise RuntimeError(
                                    f"VDN-H3 unexpected 2D attention shape "
                                    f"{tuple(softmax_out.shape)}; expected "
                                    f"({s}, {heads * head_dim})")
                        elif softmax_out.ndim == 3:
                            if softmax_out.shape[0] == heads and softmax_out.shape[1] == s:
                                softmax_out = softmax_out.transpose(0, 1).contiguous()
                            elif not (softmax_out.shape[0] == s and
                                      softmax_out.shape[1] == heads and
                                      softmax_out.shape[2] == head_dim):
                                raise RuntimeError(
                                    f"VDN-H3 unexpected 3D attention shape "
                                    f"{tuple(softmax_out.shape)}; expected "
                                    f"({s}, {heads}, {head_dim})")
                        else:
                            raise RuntimeError(
                                f"VDN-H3 unexpected attention rank "
                                f"{softmax_out.ndim}: {tuple(softmax_out.shape)}")

                        flat = (softmax_out * gate.view(s, heads, 1).to(softmax_out.dtype)) \\
                            .reshape(s, -1)
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--comfy-ui", default=str(Path.home() / "ComfyUI"))
    args = parser.parse_args()

    comfy = Path(args.comfy_ui).expanduser().resolve()
    target = comfy / "custom_nodes" / "ComfyUI-VDN-H3-24GB" / "vdn_h3_24gb" / "hybrid.py"

    if not target.is_file():
        raise SystemExit(f"VDN hybrid.py not found: {target}")

    text = target.read_text(encoding="utf-8")
    if MARKER in text:
        print("VDN ComfyUI-0.36 shape patch already installed.")
        return 0

    if OLD not in text:
        raise SystemExit(
            "Expected VDN gate block not found. The installed VDN version differs "
            "from the pinned/tested revision; refusing to patch it blindly."
        )

    backup = target.with_name(target.name + ".comfy036-shape.bak")
    if not backup.exists():
        backup.write_text(text, encoding="utf-8")
        print(f"Backup written: {backup}")

    target.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    compile(target.read_text(encoding="utf-8"), str(target), "exec")
    print(f"Patched: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())