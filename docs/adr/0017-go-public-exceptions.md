# ADR-0017 exceptions register

Companion to [ADR-0017](0017-go-public-criteria.md). A public PixelOven repository may
stay public when every criterion passes or has a recorded, operator-approved exception.
This file is where those exceptions are recorded. It is not an ADR: entries are added
or retired as repositories change, and ADR-0017 itself is not edited.

Each entry names the repository or group, the criteria it is exempt from, the reason,
and the operator's approval date. The criteria failures come from the 2026-10-26
retroactive go-public review of the public PixelOven repositories.

An exception means the repository is left as it is: no content fix, history rewrite,
visibility change, licence change or branch cleanup is planned for it.

## Exceptions

| Repository | Exempt from | Reason | Approved |
|---|---|---|---|
| `pixeloven` (archived) | C1 (employer and colleague content, internal hosts in history and commit metadata), C3 (README names the employer), C5 (no secret scanning or push protection) | Legacy project run as open source with the maintainer's employer and its engineers. It is archived and unmaintained, and the operator chose to keep it public and untouched. Third-party forks already hold public copies of its history. | 2026-10-27 |
| `typescript-react-component-library` (archived) | C1 (private repository name and colleague identities in history), C5 (no secret scanning or push protection), C6 (no LICENSE file) | Same as `pixeloven`: a legacy project run as open source with the maintainer's employer and its engineers, archived and kept public and untouched by the operator's choice. | 2026-10-27 |
| `gatsby-v2-typescript-starter` (archived) | C6 (no LICENSE file; `package.json` declares MIT) | Archived 2018-era starter with no other failing criterion. The operator chose to leave it as it is. | 2026-10-27 |
| `pixeloven.com` | C2 (no required status checks), C4 (write default token; `tokens-drift.yml` has no `permissions:` block), C5 (no secret scanning, push protection, Dependabot alerts or CodeQL), C6 (GPL-3.0 rather than MIT; commercial template in the tree and history) | The operator's personal public website. The operator chose to keep it public and untouched. | 2026-10-27 |
| Forks and side projects: the forks `no-mistakes`, `pi-web`, `pi-mcp-adapter`, `qmd`, `CodeGraphContext`, `smart-comfyui-gallery`, `ComfyUI-Distributed`, `ComfyUI-Blender`, `SageAttention-Wheels-Archive`, `ComfyUI-React-Extension-Template` and `TRELLIS`; the side projects `ComfyUI-Docker`, `SageAttention-Wheels`, `TRELLIS-Docker` and `kiln` | Whichever of C2 to C6 each fails in the review: stale or copied upstream branches and missing tag or branch rules (C2), missing LICENSE, NOTICE or fork banner (C3, C6), write default token and upstream CI running on forks (C4), missing security features (C5), and `kiln`'s GPL-3.0 licence (C6). All pass C1. | Outside the nine core repositories (`operator`, `crew`, `infra-skills`, `planning-skills`, `identity-skills`, `language-skills`, `marketplace`, `dotfiles`, `design`), which are hardened separately. The operator saw no change these repositories need. | 2026-10-27 |

## Retiring an exception

When a repository later passes the criteria it was exempt from, or is made private,
archived or deleted, remove or update its row in the same change that records why.
