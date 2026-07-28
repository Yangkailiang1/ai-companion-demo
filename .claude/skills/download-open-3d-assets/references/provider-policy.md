# Provider policy

| Provider | Default | Automation | Public repository |
|---|---|---|---|
| Poly Haven | CC0 whitelist | Public metadata/files API | Allowed with provenance |
| ambientCG | CC0 whitelist | Public full_json API and direct ZIP | Allowed with provenance |
| Kenney | CC0 whitelist per official asset page | Direct ZIP may change | Allowed when page says CC0 |
| Quaternius | CC0 whitelist per official pack page | Usually itch.io widget/manual | Allowed when page says CC0 |
| KayKit itch.io | CC0 per official pack page | Prefer user-downloaded archive | Allowed with page snapshot/URL |
| BlenderKit / Sketchfab | Mixed license | Per-asset only | Manual review |
| Objaverse / Objaverse-XL | Mixed object licenses | Research filtering | Not a blanket asset source |
| 3D-FRONT | Research-only agreement | Isolated research storage | Rejected |
| Atomic Realm Modular Roads | Commercial use but no redistribution | User archive only | Rejected from public asset library |

Every accepted record needs:

```json
{
  "schema_version": 1,
  "asset_id": "stable_snake_case",
  "provider": "provider_name",
  "official_page": "https://...",
  "download_url": "https://...",
  "license": "CC0-1.0",
  "redistribution": "allowed",
  "accessed_at": "YYYY-MM-DD",
  "expected_sha256": "",
  "intended_archetype": "static_furniture"
}
```

Downloaded files remain quarantined until archive safety, format, license, axes,
physical scale, performance and visual checks pass.
