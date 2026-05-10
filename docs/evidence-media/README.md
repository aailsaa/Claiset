# Evidence media (`docs/evidence-media/`)

This folder holds **defense / grading** screenshots (`.png`) and screen recordings (`.mov`).

## What’s here (2026-05-09 bundle)

- **`MEDIA_MAPPING.txt`** — each final filename → original macOS **Screenshot / Screen Recording …** name (or rename/split lineage).
- **Videos:** **`S1-terraform-apply-or-infra-recording.mov`**, **`C2-uat-on-merge.mov`**, **`C6-uat-zero-downtime.mov`**, **`O3-grafana-and-oauth.mov`**, **`O6-grafana-query-loki-microservices.mov`**.
- **`../evidence-media-checklist.md`** — embeds the main stills and links every file here.

## Naming

- **`A1-` … `O5-`** — align with the checklist IDs in `../evidence-media-checklist.md`.
- **`EXTRA-`** — helpful context (prod app, login, outfits, stats, duplicate `kubectl` wide, Grafana disk I/O panel).

## Before you commit large videos

`.mov` files are **large** (~20–40 MB each). If the course allows an external upload, you can keep only **`MEDIA_MAPPING.txt` + screenshots** in git and deliver recordings separately.
