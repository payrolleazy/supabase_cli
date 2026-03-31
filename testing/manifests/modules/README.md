# Module Manifests

Each module manifest defines the ordered certification contract for one module.

Required fields:
- `module_code`
- `display_name`
- `suite_order`

Each entry in `suite_order` should define:
- `suite_type`
- `suite_code`
- `mode`

Supported `suite_type` values:
- `smoke`
- `pgtap`
- `gateway`
- `load`

Supported `mode` values:
- `required`
- `not_applicable`
- `not_configured`

Rules:
- keep suite order aligned with the actual module certification sequence
- mark unavailable layers explicitly instead of omitting them
- use `shared` gateway suites when the module has no direct CRUD tunnel yet
