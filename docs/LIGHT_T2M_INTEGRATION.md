# Light-T2M integration experiment

## Decision

The game uses a hybrid motion system:

```text
player text
  -> existing LLM structured decision + deterministic MotionIntentRouter
  -> common action: reviewed AnimationPlayer clip
  -> expression: CharacterExpressionDriver -> penguin morph targets
  -> unknown explicit physical action: pending Light-T2M request
  -> offline/server generation -> canonical (T, 22, 3) joints
  -> validation -> retarget/IK/foot lock -> reviewed Godot animation clip
```

The library path remains the real-time path. Light-T2M is not called for ordinary
conversation, questions about an action, or negated instructions. Unknown physical
requests currently use a safe `idle`/known-animation fallback while retaining a
generation prompt in metadata. The current Godot runtime does **not** claim that the
generated action has already run.

## Why Light-T2M is a provider, not a Godot model

The official implementation reports 4.48M trainable motion-model parameters, but its
runtime also requires PyTorch, CLIP, diffusion schedulers, and a custom Mamba/CUDA
extension. The authors tested Python 3.10.14, PyTorch 2.2.2, CUDA 12.1, and RTX 3090.
The official Mamba setup identifies macOS as x86_64 and builds CUDA extensions, so the
current Apple Silicon machine is not a supported inference host.

The official sampler creates a 263-dimensional HumanML3D representation and saves
joint positions after `recover_from_ric(..., 22)`. Its output is `(T, 22, 3)`, not
local bone rotations. A name map alone cannot make it playable.

## Character mapping

- Body: `data/humanml3d_penguin_bone_map.json` maps the 22 canonical joints to the
  character's core body bones.
- Penguin visual forward is local `+Z`; source axes require calibration.
- Source spine joints must be resampled across the target `spine/chest` chain. Duplicate
  targets must never be assigned sequentially.
- AgentBase/NavMesh owns world translation. Generated root motion is separated from
  the in-place pose.
- Retargeting must reconstruct constrained rotations from joint directions, preserve
  target rest-pose bone lengths, limit twist, and apply foot locking.
- First integration should export reviewed GLB/Godot Animation clips. Direct realtime
  Skeleton3D writes would compete with AnimationPlayer and are deferred.

## Facial mapping

The penguin GLB exposes `joy`, `angry`, `blink`, and `a/i/u/e/o` morph targets across
four meshes. `CharacterExpressionDriver` discovers them recursively without imported
node paths and cross-fades them independently of body animation. Happy, angry, blink,
and basic talk are direct mappings; sad, surprised, excited, and bored are documented
approximations until dedicated shapes are authored.

## Motion lab

`motion_lab/` is a server-deployable package. It contains contracts, validators, an
official-sampler batch wrapper, and a separate router-training seed. The following are
ignored: upstream source checkout, checkpoints, HumanML3D, generated arrays, and
virtual environments.

The current local experiment verifies:

- official source revision can be checked out;
- this Apple Silicon host is correctly reported as unsupported for official inference;
- request JSONL and `(T,22,3)` output schemas can be validated;
- 14+ Chinese/English routing cases, 22 bone entries, and live Godot morph writes pass.

Actual pretrained generation still requires the official `hml3d.ckpt`, dependency
archive/Mean/Std files, and a Linux NVIDIA server. The author's public checkpoint link
is hosted on OneDrive; automated unauthenticated metadata access currently returns
401, so no third-party checkpoint mirror is substituted.

## Training recommendation

Do not train Light-T2M from scratch yet. First generate 5–10 representative clips with
the official checkpoint and measure semantic match, bone-length error, joint-limit
violations, and foot sliding after retargeting. Train only the small routing classifier
if catalog selection proves unreliable; fine-tune/distill the motion provider only
after collecting character-specific motion and retargeting evaluation data.

## References

- Official implementation: https://github.com/qinghuannn/light-t2m
- Paper: https://arxiv.org/abs/2412.11193
- HumanML3D: https://github.com/EricGuo5513/HumanML3D
