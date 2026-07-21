# AI Companion Motion Lab

This folder is the deployable ML side of the project. It is deliberately isolated
from the Godot runtime and contains no secrets, model weights, datasets, or generated
motion binaries in Git.

## Architecture

1. Godot routes common requests to its deterministic animation/expression library.
2. Unknown physical motions may be sent to a server implementing the JSONL contract
   in `configs/motion_contract.example.jsonl`.
3. The server runs the official Light-T2M implementation and returns canonical
   HumanML3D 22-joint motion.
4. An offline conversion step retargets the canonical skeleton to the penguin and
   exports a reviewed animation clip. Generated output is never executed as arbitrary
   code and never bypasses Godot's action validation.

## Server setup target

- Linux x86_64
- Python 3.10.14
- NVIDIA CUDA 12.1
- PyTorch 2.2.2
- Official Light-T2M checkout at `vendor/light-t2m`
- Official `hml3d.ckpt` at `checkpoints/hml3d.ckpt`
- Light-T2M dependency bundle at `vendor/light-t2m/deps`

The upstream project was tested on RTX 3090 GPUs and uses Mamba/CUDA extensions. The
current Apple Silicon development machine is suitable for contract, catalog, and
retargeting tests, but is not treated as a supported Light-T2M inference host.

## Reproduce on a GPU server

```bash
git clone https://github.com/qinghuannn/light-t2m.git vendor/light-t2m
python3.10 -m venv .venv
source .venv/bin/activate
pip install -r requirements-server.txt
pip install -r vendor/light-t2m/requirements.txt
pip install -e vendor/light-t2m/mamba
python scripts/validate_contract.py configs/motion_contract.example.jsonl
```

Download the official dependency archive and pretrained checkpoint from the links in
the upstream README. Their licenses and the HumanML3D/SMPL terms must be reviewed
before any public or commercial distribution.

Training data, checkpoints, generated motions, virtual environments, and vendored
upstream code are ignored by the project `.gitignore`.
