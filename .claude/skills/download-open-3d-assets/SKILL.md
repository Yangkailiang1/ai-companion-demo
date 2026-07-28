---
name: download-open-3d-assets
description: Safely audit and download small batches of redistributable 3D assets from approved open sources, producing provenance manifests, hashes, archive inventories, and quarantine outputs. Use when sourcing CC0 furniture, props, materials, or modular environment assets for this public Godot project; also use when reviewing local itch.io ZIP archives before extraction. Reject mixed, unknown, research-only, attribution-only, or no-redistribution licenses from the public asset library.
---

# Download Open 3D Assets

Read `CLAUDE.md`, `docs/ASSET_PROVENANCE.md`, and
`references/provider-policy.md`. Keep network downloads outside `res://` until accepted.

## Workflow

1. Resolve the exact official asset page and license. “Free” is not a license.
2. Classify the source:
   - `approved_cc0`: Poly Haven, ambientCG, Kenney asset pages, Quaternius asset pages,
     or another page whose official record explicitly states CC0.
   - `manual_review`: mixed-license libraries, itch.io pages without redistribution
     permission, attribution licenses, or paid terms.
   - `rejected_public`: research-only, noncommercial, no-redistribution, unknown.
3. Limit an unreviewed batch to three assets of one archetype and one visual style.
4. Write one JSON provenance manifest per archive/file. Include official page,
   direct download URL, license, author/provider, access date, intended role and
   expected SHA-256 when known.
5. Download only to a task-specific quarantine directory. Use
   `scripts/download_manifest.py`; configure `HTTPS_PROXY=http://127.0.0.1:7890`
   when the user requests the local proxy.
6. For ZIP files run `scripts/audit_asset_archive.py`. Reject path traversal,
   symlinks, executables, nested archives, missing model formats, and excessive
   uncompressed size.
7. Do not extract into the Godot project. Hand accepted manifests and archives to
   `$build-parametric-asset-library`.
8. Report downloads, bytes, hashes, license evidence, rejected candidates and
   retryable network failures. Never commit archives automatically.

## Provider rules

- Prefer official APIs over page scraping.
- Poly Haven: use the public assets/files API and preserve required dependencies.
- ambientCG: use `/api/v2/full_json`; the current API may not honor `type=3DModel`,
  so verify returned `dataType` locally or resolve a known asset ID.
- Kenney: direct asset ZIP URLs can change; record the official asset page alongside
  the resolved URL.
- Quaternius and itch.io: browser purchase/download widgets may require a user
  session. Do not automate around access controls; accept a user-downloaded archive.
- Never accept Sketchfab, BlenderKit, Objaverse, or marketplace entries without a
  per-asset license record.

Codex owns license acceptance, visual review, project promotion and Git operations.
