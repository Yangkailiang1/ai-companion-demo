# Generated motion

Light-T2M outputs and retargeted clips are written here during server experiments.
Binary output is ignored until a clip is reviewed, converted to a game asset, and its
provenance is documented.

Retarget packages created by `motion_lab/scripts/retarget_humanml3d_motion.py` are
also written under this tree by default:

```text
library/<motion_id>/motion_package.json
library/<motion_id>/source_positions.npy
library/<motion_id>/target_rotations.npy
library/<motion_id>/root_motion.npy
library/<motion_id>/foot_contacts.npy
```
